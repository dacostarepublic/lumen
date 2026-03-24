class Lumen < Formula
  desc "Terminal-first wallpaper manager for macOS"
  homepage "https://github.com/dacostarepublic/lumen"
  version "1.1.0"
  url "https://github.com/dacostarepublic/lumen/releases/download/v1.1.0/lumen-v1.1.0-macos.tar.gz"
  sha256 "b8f68df558306d505cdfbeedcc451ac9ae2eb5d20ff8bb557638de7c23407fca"
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
