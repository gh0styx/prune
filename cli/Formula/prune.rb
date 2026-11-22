# Homebrew formula for the prune CLI (terminal companion to Prune.app).
# Local draft: the tap gh0styx/homebrew-tap does not exist yet, and the url and sha256 below
# point at a tag that is not published yet. Fill them in when the CLI is released.
class Prune < Formula
  desc "Find and clean reclaimable disk space on macOS from the terminal"
  homepage "https://prune.gh0styx.com"
  url "https://github.com/gh0styx/prune/archive/refs/tags/cli-v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "GPL-3.0-only"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :ventura

  def install
    cd "cli" do
      system "swift", "build", "--disable-sandbox", "--configuration", "release"
      bin.install ".build/release/prune"
    end
  end

  test do
    assert_match "prune #{version}", shell_output("#{bin}/prune --version")
    # Dry run only: the test never removes anything.
    assert_match "node_modules", shell_output("#{bin}/prune purge --root #{testpath}")
  end
end
