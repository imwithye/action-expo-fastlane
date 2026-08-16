# Shared Expo config resolution for the Appfile and Fastfile.
#
# Resolved once per fastlane process and memoized: fastlane re-evaluates the
# Appfile on every credentials lookup, and an app.config.js/ts project would
# otherwise pay a full `npx expo config` subprocess each time. `require`
# caches this file, so the memo survives those re-evaluations.
require "json"

module ExpoConfig
  # This file is `require`d as a real file, so __dir__ is the lane directory —
  # unlike the Fastfile and Appfile, which fastlane evaluates through `eval`
  # and where __dir__ is "." / nil. Both take their paths from here.
  LANE_DIR = __dir__
  ROOT = File.expand_path("..", LANE_DIR)

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

  # Points the app icon at path (relative to the project root) — prebuild
  # generates the whole AppIcon set from it, flattening the alpha channel
  # onto white the way the App Store requires.
  #
  # ios.icon overrides the top-level icon, and can itself be either a path or
  # a { light, dark, tinted } object, so it is replaced wholesale with the
  # single path rather than merged: every appearance gets the same icon.
  # Returns false when there is no app.json to edit (dynamic config).
  def self.set_icon(path)
    return false unless File.exist?(app_json_path)
    json = JSON.parse(File.read(app_json_path))
    cfg = json["expo"] || json
    cfg["icon"] = path
    (cfg["ios"] ||= {})["icon"] = path
    write_app_json(json)
    true
  end

  def self.write_app_json(json)
    File.write(app_json_path, JSON.pretty_generate(json) + "\n")
    @config = nil # the memo is now stale
  end
  private_class_method :write_app_json
end
