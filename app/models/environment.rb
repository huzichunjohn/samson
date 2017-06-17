# frozen_string_literal: true
class Environment < ActiveRecord::Base
  has_soft_deletion default_scope: true
  audited

  include Permalinkable

  has_many :deploy_groups
  has_many :template_stages, -> { where(is_template: true) }, through: :deploy_groups, class_name: 'Stage'
  has_one :lock, as: :resource

  validates_presence_of :name
  validates_uniqueness_of :name

  # also used by private plugin
  def self.env_deploygroup_array(include_all: true)
    all = include_all ? [["All", nil]] : []
    envs = Environment.all.map { |env| [env.name, "Environment-#{env.id}"] }
    separator = [["----", nil]]
    deploy_groups = DeployGroup.all.sort_by(&:natural_order).map { |dg| [dg.name, "DeployGroup-#{dg.id}"] }
    all + envs + separator + deploy_groups
  end

  private

  def permalink_base
    name
  end
end
