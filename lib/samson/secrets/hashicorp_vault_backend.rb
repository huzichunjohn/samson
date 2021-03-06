# frozen_string_literal: true
require 'vault'

module Samson
  module Secrets
    class BackendError < StandardError
    end

    class HashicorpVaultBackend
      # / means diretory in vault and we want to keep all the keys in the same folder
      DIRECTORY_SEPARATOR = "/"
      KEY_SEGMENTS = 4

      class << self
        def read(key)
          return unless key
          result = vault_action(:read, vault_path(key, :encode))
          return if !result || result.data[:vault].nil?

          result = result.to_h
          result = result.merge(result.delete(:data))
          result[:value] = result.delete(:vault)
          result
        end

        def read_multi(keys)
          # will be used inside the threads and can lead to errors when not preloaded
          # reproducible by running a single test like hashicorp_vault_backend_test.rb -n '/filter_keys_by_value/'
          SecretStorage.name

          found = {}
          Samson::Parallelizer.map(keys, db: true) do |key|
            begin
              if value = read(key)
                found[key] = value
              end
            rescue # deploy group has no vault server or deploy group no longer exists
              nil
            end
          end
          found
        end

        def write(key, data)
          user_id = data.fetch(:user_id)
          current = read(key)
          creator_id = (current && current[:creator_id]) || user_id
          data = data.merge(creator_id: creator_id, updater_id: user_id)

          begin
            deep_write(key, data)
          rescue
            revert(key, current)
            raise
          end
        end

        def delete(key)
          vault_action(:delete, vault_path(key, :encode))
        end

        def keys
          keys = vault_action(:list_recursive, "")
          keys.uniq! # we read from multiple backends that might have the same keys
          keys.map! { |secret_path| vault_path(secret_path, :decode) }
        end

        def filter_keys_by_value(keys, value)
          all = read_multi(keys)
          all.map { |k, v| k if Rack::Utils.secure_compare(v.fetch(:value), value) }.compact
        end

        def deploy_groups
          DeployGroup.where.not(vault_server_id: nil)
        end

        private

        def revert(key, current)
          if current
            deep_write(key, current)
          else
            delete(key)
          end
        rescue
          nil # ignore errors in here
        end

        def deep_write(key, data)
          important = {vault: data.fetch(:value)}.merge(data.slice(:visible, :comment, :creator_id, :updater_id))
          vault_action(:write, vault_path(key, :encode), important)
        end

        def vault_action(method, path, *args)
          vault_client.public_send(method, path, *args)
        rescue Vault::HTTPConnectionError => e
          raise Samson::Secrets::BackendError, "Error talking to vault backend: #{e.message}"
        end

        def vault_client
          Samson::Secrets::VaultClient.client
        end

        # key is the last element and should not include directories
        def vault_path(key, direction)
          parts = key.split(DIRECTORY_SEPARATOR, KEY_SEGMENTS)
          raise ActiveRecord::RecordNotFound, "Invalid key #{key.inspect}" unless last = parts[KEY_SEGMENTS - 1]
          convert_path!(last, direction)
          parts.join(DIRECTORY_SEPARATOR)
        end

        # convert from/to escaped characters
        def convert_path!(string, direction)
          case direction
          when :encode then string.gsub!(DIRECTORY_SEPARATOR, "%2F")
          when :decode then string.gsub!("%2F", DIRECTORY_SEPARATOR)
          else raise ArgumentError, "direction is required"
          end
          string
        end
      end
    end
  end
end
