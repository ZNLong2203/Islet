cask "islet" do
  version "0.2.0"
  sha256 "50b0fcb9be9b6018215b04a15d43c6cae03dba7f6ed723353d32c45b8ff78a81"

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
