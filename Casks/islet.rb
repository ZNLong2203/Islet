cask "islet" do
  version "0.1.0"
  sha256 "a8c8e0446215719dbebcc8090afd3ebefa93e538ff9887d09cf01e41a03ed8c1"

  url "https://github.com/ZNLong2203/Islet/releases/download/v#{version}/Islet-#{version}.zip"
  name "Islet"
  desc "Live activities, music, notes and a file shelf in the MacBook notch"
  homepage "https://github.com/ZNLong2203/Islet"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Islet.app"

  # Islet is ad-hoc signed rather than notarized, so clear the download quarantine or
  # Gatekeeper refuses to open it. Then start it right away, including after `brew upgrade`.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Islet.app"]
    system_command "/usr/bin/open", args: ["#{appdir}/Islet.app"]
  end

  uninstall signal: [["TERM", "io.github.znlong2203.islet"]]

  zap trash: "~/Library/Preferences/io.github.znlong2203.islet.plist"
end
