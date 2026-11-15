cask "cpaste" do
  version "0.1.7"
  sha256 "6adcfe6b462e4df049f6aa28975fc327c24fa539c8ee0b9b28716cfc5bc3f3ca"

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
