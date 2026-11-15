cask "cpaste" do
  version "0.1.8"
  sha256 "bf2410f55fe357aed13f116ba23a09feda7d450b59994dc2570b8a6fdce39032"

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
