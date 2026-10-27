# Template cask. Copy into your tap (homebrew-<name>/Casks/) and fill in version and sha256
# (the release workflow prints the sha256).
cask "sweepkey" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/thisisprabhat/sweepkey/releases/download/v#{version}/Sweepkey-#{version}.dmg"
  name "Sweepkey"
  desc "Developer-disk cleaner and secrets vault"
  homepage "https://github.com/thisisprabhat/sweepkey"

  depends_on macos: :tahoe

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "Sweepkey.app"
  # The CLI ships inside the app bundle.
  binary "#{appdir}/Sweepkey.app/Contents/Resources/sweepkey"

  zap trash: [
    "~/Library/Application Support/Sweepkey",
    "~/Library/Preferences/com.prabhatkumar.Sweepkey.plist",
  ]
end
