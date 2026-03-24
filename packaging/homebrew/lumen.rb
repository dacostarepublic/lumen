class Lumen < Formula
  desc "Terminal-first wallpaper manager for macOS"
  homepage "https://github.com/dacostarepublic/lumen"
  version "2.0.0"
  url "https://github.com/dacostarepublic/lumen/releases/download/v2.0.0/lumen-v2.0.0-macos.tar.gz"
  sha256 "5509498a294c88b231863cd8b347adc34b576562f75ca0fb40170cd9cd621f47"
  license "MIT"

  depends_on macos: :ventura

  def install
    bin.install "lumen"
  end

  test do
    output = shell_output("#{bin}/lumen --version")
    assert_match version.to_s, output

    path_output = shell_output("#{bin}/lumen config path")
    assert_match ".lumen-config", path_output
  end
end
