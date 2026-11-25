require "net/http"
require "json"

module Capture
  # Pushes a set of files to a repository as one commit, over GitHub's Git Data API.
  #
  # One commit, not one per file: blobs, then a tree, then a commit, then move the branch.
  # If the branch does not exist yet it is created; if the repository is empty the commit
  # has no parent. Either way the person ends up with one entry in their history per
  # backup, which is what makes the history readable afterwards.
  class GitPush
    class Error < StandardError; end

    API = "https://api.github.com".freeze
    Result = Struct.new(:commit_sha, :files, :created_branch, keyword_init: true)

    def self.call(backup, files, message:, http: nil) = new(backup, http: http).call(files, message)

    def initialize(backup, http: nil)
      @backup = backup
      @http = http || Net::HTTP
    end

    # files: { "path/in/repo.md" => "contents" }
    def call(files, message)
      raise Error, "Nothing to back up" if files.empty?

      base = branch_head
      blobs = files.transform_values { |content| post("/git/blobs", content: Base64.strict_encode64(content.to_s), encoding: "base64")["sha"] }
      tree = post("/git/trees", {
        base_tree: base && tree_of(base),
        tree: blobs.map { |path, sha| { path: path, mode: "100644", type: "blob", sha: sha } }
      }.compact)
      commit = post("/git/commits", message: message, tree: tree["sha"], parents: [base].compact)

      if base
        patch("/git/refs/heads/#{@backup.branch}", sha: commit["sha"])
      else
        post("/git/refs", ref: "refs/heads/#{@backup.branch}", sha: commit["sha"])
      end
      Result.new(commit_sha: commit["sha"], files: files.size, created_branch: base.nil?)
    end

    # Cheap check that the token works and can write, before anyone waits on a push.
    def check!
      repo = get("/")
      raise Error, "That token cannot write to #{@backup.repo}" unless repo.dig("permissions", "push")
      repo
    end

    private

    def branch_head
      ref = get("/git/ref/heads/#{@backup.branch}", allow_missing: true)
      ref&.dig("object", "sha")
    end

    def tree_of(commit_sha) = get("/git/commits/#{commit_sha}").dig("tree", "sha")

    def path(suffix) = "/repos/#{@backup.repo}#{suffix == '/' ? '' : suffix}"

    def get(suffix, allow_missing: false) = request(Net::HTTP::Get, suffix, nil, allow_missing: allow_missing)
    def post(suffix, body) = request(Net::HTTP::Post, suffix, body)
    def patch(suffix, body) = request(Net::HTTP::Patch, suffix, body)

    def request(klass, suffix, body, allow_missing: false)
      uri = URI("#{API}#{path(suffix)}")
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{@backup.token}"
      req["Accept"] = "application/vnd.github+json"
      req["X-GitHub-Api-Version"] = "2022-11-28"
      # A generic client name: the firm's identity is not the API's business.
      req["User-Agent"] = "skill-capture"
      req.body = JSON.generate(body) if body

      response = @http.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |h| h.request(req) }
      return nil if allow_missing && response.code == "404"
      unless response.code.start_with?("2")
        raise Error, friendly(response)
      end
      response.body.present? ? JSON.parse(response.body) : {}
    rescue JSON::ParserError => e
      raise Error, "GitHub sent something unreadable: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "Could not reach #{@backup.host}: #{e.class}"
    end

    # Say what the person has to do, not what the status code was.
    def friendly(response)
      detail = (JSON.parse(response.body)["message"] rescue nil)
      case response.code
      when "401" then "That token was refused. It may have expired, or been revoked."
      when "403" then "That token is not allowed to do this. It needs Contents: read and write on #{@backup.repo}."
      when "404" then "#{@backup.repo} was not found. Check the name, and that the token can see it."
      when "409" then "The branch moved while we were writing. Try again."
      when "422" then "GitHub refused the change: #{detail}"
      else "GitHub returned #{response.code}#{": #{detail}" if detail}"
      end
    end
  end
end
