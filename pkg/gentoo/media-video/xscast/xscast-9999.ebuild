EAPI="6"

inherit git-r3

DESCRIPTION="a tool for creating mini-screencasts of a terminal or other window"
HOMEPAGE="http://keyboardfire.com/"
EGIT_REPO_URI="https://github.com/KeyboardFire/xscast.git"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE=""

DEPEND="
	virtual/ffmpeg
	media-gfx/imagemagick
	x11-apps/xinput
	x11-apps/xwininfo
	x11-misc/dzen:2
	"
RDEPEND="${DEPEND}"

src_install() {
	newbin "${S}/xscast.sh" xscast
	doman xscast.1
}
