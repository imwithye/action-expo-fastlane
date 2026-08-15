# Shared Expo config resolution for the Appfile and Fastfile.
#
# Resolved once per fastlane process and memoized: fastlane re-evaluates the
# Appfile on every credentials lookup, and an app.config.js/ts project would
# otherwise pay a full `npx expo config` subprocess each time. `require`
# caches this file, so the memo survives those re-evaluations.
require "json"

module ExpoConfig
  ROOT = File.expand_path("..", __dir__)

  # The action exports its inputs unconditionally, so an unset input arrives
  # as an empty string — treat that the same as absent.
  def self.env(name)
    value = ENV[name].to_s
    value.empty? ? nil : value
  end

  def self.app_json_path
    File.join(ROOT, "app.json")
  end

  def self.config
    @config ||=
      if File.exist?(app_json_path)
        json = JSON.parse(File.read(app_json_path))
        json["expo"] || json
      else
        # app.config.js/ts projects: let Expo resolve the config itself.
        JSON.parse(Dir.chdir(ROOT) { `npx expo config --json` })
      end
  end

  def self.package_json
    @package_json ||=
      begin
        path = File.join(ROOT, "package.json")
        File.exist?(path) ? JSON.parse(File.read(path)) : {}
      end
  end

  # True when the app depends on the package directly (a transitive copy in
  # node_modules is not enough — the native module has to be autolinked).
  def self.dependency?(name)
    %w[dependencies devDependencies].any? { |group| package_json[group].is_a?(Hash) && package_json[group].key?(name) }
  end

  def self.bundle_identifier
    env("APP_IDENTIFIER") || config.dig("ios", "bundleIdentifier")
  end

  def self.team_id
    env("APPLE_TEAM_ID") || config.dig("ios", "appleTeamId")
  end

  # Stamps ios.buildNumber into app.json — prebuild bakes it into the native
  # project, so it has to land before prebuild runs. Returns false when there
  # is no app.json to edit (dynamic config); those projects map BUILD_NUMBER
  # themselves.
  def self.stamp_build_number(build_number)
    return false unless File.exist?(app_json_path)
    json = JSON.parse(File.read(app_json_path))
    cfg = json["expo"] || json
    (cfg["ios"] ||= {})["buildNumber"] = build_number
    write_app_json(json)
    true
  end

  def self.write_app_json(json)
    File.write(app_json_path, JSON.pretty_generate(json) + "\n")
    @config = nil # the memo is now stale
  end
  private_class_method :write_app_json
end
