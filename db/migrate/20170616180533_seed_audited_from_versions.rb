# frozen_string_literal: true
class SeedAuditedFromVersions < ActiveRecord::Migration[5.1]
  IGNORED = ['id', 'order', 'token', 'created_at', 'updated_at'].freeze

  class Version < ActiveRecord::Base
    self.table_name = 'versions'
  end

  class Audit < ActiveRecord::Base
  end

  def up
    Version.distinct.pluck(:item_type, :item_id).each do |type, id|
      previous_version = nil
      @number = -1

      Version.where(item_type: type, item_id: id).find_each do |version|
        create_audit(previous_version, version.object) if previous_version
        previous_version = version
      end

      # can fail if class is not defined, but then we treat it as deleted ...
      current_state = begin
        if model = type.constantize.find_by_id(id)
          attributes = model.attributes
          attributes['script'] = model.script if type == "Stage"
          attributes.to_yaml
        else
          "{}"
        end
      rescue NameError
        puts "Unable to find constant #{type} -- #{$!} -- #{$!.class}"
        "{}"
      end
      create_audit(previous_version, current_state)
    end
  end

  def down
    Audit.where(request_uuid: 'migrated').delete_all
  end

  private

  def create_audit(version, current_state)
    previous_state = YAML.load(version.object || "{}").except(*IGNORED)
    current_state = YAML.load(current_state || "{}").except(*IGNORED)

    # audited has a strange behavior where the create/destroy changes don't have arrays but just a value
    simple = ["create", "destroy"].include?(version.event)
    diff = (simple ? current_state : hash_change(previous_state, current_state))
    return if diff == {} && version.event == "update"

    @number += 1

    if version.whodunnit =~ /^\d+$/
      user_id = version.whodunnit
      username = nil
    else
      user_id = nil
      username = version.whodunnit
    end

    Audit.create!(
      auditable_id: version.item_id,
      auditable_type: version.item_type,
      user_id: user_id,
      user_type: "User",
      username: username,
      action: version.event,
      audited_changes: diff.to_yaml,
      version: @number,
      created_at: version.created_at,
      request_uuid: 'migrated'
    )
  rescue
    puts "ERROR processing #{version.id} (#{version.item_type}:#{version.item_id}) -- #{$!}"
    puts $!.backtrace.select { |l| l.include?(__FILE__) }
    abort
  end

  # {a: 1}, {a:2, b:3} -> {a: [1, 2], b: [nil, 3]}
  def hash_change(before, after)
    (after.keys + before.keys).uniq.each_with_object({}) do |k, change|
      change[k] = [before[k], after[k]] unless before[k] == after[k]
    end
  end
end
