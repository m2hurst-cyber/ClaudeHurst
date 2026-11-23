module Capture
  # The default field taxonomy, created once if the table is empty. Admins edit it afterwards.
  module Taxonomy
    DEFAULT = {
      "Finance" => [%w[finance], {
        "Accounting" => [%w[ledger journal accounting], {
          "Reconciliation" => [%w[reconcil match unmatched bank statement], {}],
          "Month-end close" => [%w[month-end close accrual trial balance], {}]
        }],
        "FP&A" => [%w[forecast budget variance plan], {}],
        "Treasury" => [%w[cash fx currency revalu treasury], {}],
        "Accounts payable" => [%w[invoice vendor purchase order], {}]
      }],
      "Data analysis" => [%w[data analysis analy], {
        "Data preparation" => [%w[import extract refresh export clean], {}],
        "Statistics" => [%w[statistic regression sample average distribution trend], {}],
        "Reporting" => [%w[report kpi summary dashboard pack], {}],
        "Visualization" => [%w[chart graph visual], {}]
      }],
      "Design" => [%w[design], {
        "Presentation design" => [%w[slide deck presentation template], {}],
        "Document design" => [%w[layout format styling], {}],
        "Brand" => [%w[brand logo style guide], {}]
      }],
      "Legal" => [%w[legal counsel], {
        "Contracts" => [%w[contract redline clause nda agreement sign-off], {}],
        "Compliance" => [%w[policy audit regulation compliance], {}]
      }],
      "Sales" => [%w[sales customer], {
        "Proposals & pricing" => [%w[proposal quote pricing], {}],
        "Customer communication" => [%w[email reply customer update], {}]
      }],
      "Operations" => [%w[operations], {
        "Procurement" => [%w[supplier procure vendor renewal], {}],
        "Project management" => [%w[timeline milestone status project], {}]
      }]
    }.freeze

    module_function

    def ensure_defaults!
      return if Field.exists?
      Field.transaction { build(DEFAULT, nil) }
    end

    def build(tree, parent)
      tree.each_with_index do |(name, (keywords, children)), i|
        f = Field.create!(name: name, parent: parent, keywords: keywords, position: i)
        build(children, f)
      end
    end
  end
end
