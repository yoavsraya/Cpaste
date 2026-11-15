cask "cpaste" do
  version "0.1.9"
  sha256 "49397cec2c0e905bdeaff18bddf8303f10c0c473cef21b5df6689d53fbb42305"

  url "https://github.com/yoavsraya/Cpaste/releases/download/v#{version}/Cpaste.zip"
  name "Cpaste"
  desc "Local clipboard manager with a shelf of recent clips"
  homepage "https://github.com/yoavsraya/Cpaste"

  auto_updates true
  depends_on macos: :sonoma

  app "Cpaste.app"

  zap trash: [
    "~/Library/Application Support/Cpaste",
    "~/Library/Caches/local.cpaste.app",
    "~/Library/HTTPStorages/local.cpaste.app",
    "~/Library/Preferences/local.cpaste.app.plist",
  ]

  caveats <<~EOS
    Cpaste is not signed with an Apple Developer ID. On the first launch macOS blocks it.
    Open System Settings, then Privacy & Security, and click "Open Anyway" next to Cpaste.
  EOS
end
