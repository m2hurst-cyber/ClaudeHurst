require "test_helper"

class GitBackupTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @me = make_user(role: "reviewer", domains: %w[finance], name: "Sam Ortiz")
    @other = make_user(role: "reviewer", domains: %w[finance], name: "Rae Reviewer")
    Protocol.for("git_backup").update!(enabled: true, settings: { "own_work_only" => 1 })
  end

  def publish(name, by:)
    steps = %W[a.#{name} b.#{name} c.#{name}]
    Capture::Publisher.publish!(drafted_candidate(name: name, steps: steps), reviewer: by)
  end

  def connect(**attrs)
    GitBackup.create!({ user: @me, repo: "sam/skills", token: "github_pat_abcdefgh1234" }.merge(attrs))
  end

  # A stand-in for Net::HTTP that records what was asked of GitHub.
  class FakeHttp
    attr_reader :calls
    def initialize(responses) = (@responses = responses; @calls = [])
    def start(_host, _port, **_opts)
      yield self
    end
    def request(req)
      @calls << [req.method, req.path, (JSON.parse(req.body) rescue nil)]
      key = @responses.keys.find { |m, p| m == req.method && req.path.match?(p) }
      raise "no stub for #{req.method} #{req.path}" unless key
      code, body = @responses[key]
      Struct.new(:code, :body).new(code.to_s, body ? JSON.generate(body) : "")
    end
  end

  def pushing_ok
    FakeHttp.new({
      ["GET", %r{/git/ref/heads/main}] => [200, { "object" => { "sha" => "base-sha" } }],
      ["GET", %r{/git/commits/base-sha}] => [200, { "tree" => { "sha" => "tree-sha" } }],
      ["POST", %r{/git/blobs}] => [201, { "sha" => "blob-sha" }],
      ["POST", %r{/git/trees}] => [201, { "sha" => "new-tree" }],
      ["POST", %r{/git/commits}] => [201, { "sha" => "commit-sha" }],
      ["PATCH", %r{/git/refs/heads/main}] => [200, {}]
    })
  end

  # ---------- what may leave ----------

  test "a personal backup carries the person's own work, not the firm's library" do
    mine = publish("my-own-skill", by: @me)
    theirs = publish("someone-elses", by: @other)
    names = connect.skills.map(&:name)

    assert_includes names, mine.name
    refute_includes names, theirs.name, "a backup button is not a way to take the library home"
  end

  test "a contributor's work counts as theirs" do
    skill = publish("shared-skill", by: @other)
    skill.update!(source: skill.source.merge("contributor_keys" => ["user:#{@me.id}"]))
    assert_includes connect.skills.map(&:name), skill.name
  end

  test "the firm can widen it to everything the person can see" do
    publish("someone-elses", by: @other)
    refute_includes connect.skills.map(&:name), "someone-elses"

    Protocol.for("git_backup").update!(settings: { "own_work_only" => 0 })
    assert_includes GitBackup.find_by(user: @me).skills.map(&:name), "someone-elses"
  end

  test "the firm can turn personal backups off entirely" do
    Protocol.for("git_backup").update!(enabled: false)
    sign_in @me
    post git_backup_path, params: { git_backup: { repo: "sam/skills", token: "t" } }
    assert_redirected_to settings_path
    assert_equal 0, GitBackup.count
  end

  # ---------- what gets written ----------

  test "the export is one file per skill, a manifest that pins them, and a readme" do
    publish("my-own-skill", by: @me)
    files = Capture::GitExport.files(connect(path_prefix: "skills"))

    assert_includes files.keys, "skills/my-own-skill.md"
    assert_includes files.keys, "skills/manifest.json"
    assert_includes files.keys, "skills/README.md"
    assert_match(/^---/, files["skills/my-own-skill.md"], "each file is an Agent Skills SKILL.md")

    manifest = JSON.parse(files["skills/manifest.json"])
    entry = manifest["skills"].first
    assert_equal Skill.current("my-own-skill").content_hash, entry["content_hash"],
                 "the manifest pins each file to the hash it had here, so the copy can be checked"
    assert_match(/wrote or contributed/, manifest["scope"])
  end

  test "the readme says what the copy is not, and whose the skills are" do
    publish("my-own-skill", by: @me)
    readme = Capture::GitExport.files(connect)["skills/README.md"]
    assert_match(/not the source of truth/i, readme)
    assert_match(/your employer's, not yours/i, readme)
  end

  test "an empty folder setting puts the files at the repository root" do
    publish("my-own-skill", by: @me)
    assert_includes Capture::GitExport.files(connect(path_prefix: "")).keys, "my-own-skill.md"
  end

  # ---------- the push ----------

  test "one backup is one commit, built on what is already there" do
    publish("my-own-skill", by: @me)
    backup = connect
    http = pushing_ok
    result = Capture::GitPush.call(backup, Capture::GitExport.files(backup), message: "backup", http: http)

    assert_equal "commit-sha", result.commit_sha
    refute result.created_branch
    assert_equal 1, http.calls.count { |m, p, _| m == "POST" && p.include?("/git/commits") }, "one commit, not one per file"
    assert_equal 3, http.calls.count { |m, p, _| m == "POST" && p.include?("/git/blobs") }
    tree = http.calls.find { |m, p, _| m == "POST" && p.include?("/git/trees") }.last
    assert_equal "tree-sha", tree["base_tree"], "built on the existing tree rather than replacing the repository"
  end

  test "an empty repository gets its first commit and its branch" do
    publish("my-own-skill", by: @me)
    backup = connect
    http = FakeHttp.new({
      ["GET", %r{/git/ref/heads/main}] => [404, nil],
      ["POST", %r{/git/blobs}] => [201, { "sha" => "blob" }],
      ["POST", %r{/git/trees}] => [201, { "sha" => "tree" }],
      ["POST", %r{/git/commits}] => [201, { "sha" => "first" }],
      ["POST", %r{/git/refs}] => [201, {}]
    })
    result = Capture::GitPush.call(backup, Capture::GitExport.files(backup), message: "first", http: http)
    assert result.created_branch
    assert_nil http.calls.find { |m, p, _| m == "POST" && p.include?("/git/trees") }.last["base_tree"]
    assert_empty http.calls.find { |m, p, _| m == "POST" && p.include?("/git/commits") }.last["parents"]
  end

  test "a refused token says what to do about it, not what the status code was" do
    backup = connect
    [["401", /expired, or been revoked/], ["403", /Contents: read and write/], ["404", /was not found/]].each do |code, message|
      http = FakeHttp.new({ ["GET", %r{/repos/sam/skills\z}] => [code, { "message" => "nope" }] })
      error = assert_raises(Capture::GitPush::Error) { Capture::GitPush.new(backup, http: http).check! }
      assert_match message, error.message
    end
  end

  test "connecting refuses a token that cannot write" do
    backup = connect
    http = FakeHttp.new({ ["GET", %r{/repos/sam/skills\z}] => [200, { "permissions" => { "push" => false } }] })
    error = assert_raises(Capture::GitPush::Error) { Capture::GitPush.new(backup, http: http).check! }
    assert_match(/cannot write/, error.message)
  end

  test "the token is never stored in the clear" do
    backup = connect(token: "github_pat_secretvalue")
    raw = GitBackup.connection.select_value("SELECT token FROM git_backups WHERE id = #{backup.id}")
    refute_includes raw.to_s, "secretvalue"
    assert_equal "github_pat_secretvalue", backup.reload.token
    assert_equal "alue", backup.token_hint
  end

  test "a run records where it got to, and says so in the audit log" do
    publish("my-own-skill", by: @me)
    backup = connect
    Capture::GitPush.stub(:call, Capture::GitPush::Result.new(commit_sha: "abc123", files: 3, created_branch: false)) do
      GitBackupJob.perform_now(backup.id)
    end
    backup.reload
    assert_equal "abc123", backup.last_commit_sha
    assert_equal 1, backup.last_skill_count
    assert_nil backup.last_error
    assert AuditLog.where(action: "git_backup.pushed").exists?
    assert @me.notifications.where(kind: "git_backup").exists?
  end

  test "a failure is kept on the record instead of disappearing into a log" do
    publish("my-own-skill", by: @me)
    backup = connect
    Capture::GitPush.stub(:call, ->(*) { raise Capture::GitPush::Error, "That token was refused." }) do
      GitBackupJob.perform_now(backup.id)
    end
    assert_equal "That token was refused.", backup.reload.last_error
    assert AuditLog.where(action: "git_backup.failed").exists?
  end

  # ---------- it is yours alone ----------

  test "the repository has to look like a repository" do
    backup = GitBackup.new(user: @me, repo: "not a repo", token: "t")
    refute backup.valid?
    assert_match(/owner\/repository/, backup.errors.full_messages.to_sentence)
    assert GitBackup.new(user: @me, repo: "https://github.com/sam/skills.git", token: "t").tap(&:valid?).repo == "sam/skills"
  end

  test "nobody reaches anyone else's backup" do
    connect
    sign_in @other
    post push_git_backup_path
    assert_redirected_to settings_path
    assert_nil @other.git_backup
  end

  test "settings offers it, and shows what would go" do
    publish("my-own-skill", by: @me)
    sign_in @me
    get settings_path
    assert_response :success
    assert_match(/Back up to your own Git/, response.body)
    assert_match(/1 skill/, response.body)
    assert_select "input[name=?]", "git_backup[repo]"
  end
end
