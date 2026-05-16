cask "mark-this-down" do
  version "0.1.0"
  sha256 "57a6d64d1204c4a46b501e1fd6fa2a2e57e952553741adb80ddc7fde8a5a8e48"

  url "https://github.com/LeviHirsch/mark-this-down/releases/download/v#{version}/MarkThisDown.zip"
  name "Mark This Down"
  desc "Lightweight native macOS markdown editor"
  homepage "https://github.com/LeviHirsch/mark-this-down"

  app "markthisdown.app"

  zap trash: [
    "~/Library/Preferences/com.levi.markthisdown.plist",
    "~/Library/Application Support/markthisdown",
  ]
end
