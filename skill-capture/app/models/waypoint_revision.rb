class WaypointRevision < ApplicationRecord
  belongs_to :waypoint
  belongs_to :editor, class_name: "User", optional: true
end
