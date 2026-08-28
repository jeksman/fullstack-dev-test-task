#!/usr/bin/env bash
# lib/tools.sh — local dependency detection and in-run installation.
#
# The user must never be told "install X and run deploy.sh again". Anything we
# can fetch ourselves is fetched into a repository-local .tools/bin, with the
# publisher's checksum verified before the binary is made executable.

GHO_TOOLS_DIR=""
# shellcheck disable=SC2034  # set here, consumed by deploy.sh and lib/tailscale.sh
GHO_TAILSCALE_BIN="${GHO_TAILSCALE_BIN:-}"

tools_init() {
	GHO_TOOLS_DIR="${GHO_ROOT}/.tools/bin"
	mkdir -p "$GHO_TOOLS_DIR"
	case ":${PATH}:" in
	*":${GHO_TOOLS_DIR}:"*) : ;;
	*) PATH="${GHO_TOOLS_DIR}:${PATH}" ;;
	esac
	export PATH
}

have() { command -v "$1" >/dev/null 2>&1; }

# _download <url> <dest>
_download() {
	curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
		--connect-timeout 15 --max-time 300 -o "$2" "$1"
}

# _verify_sha256 <file> <expected_hex>
_verify_sha256() {
	local actual
	if have sha256sum; then
		actual="$(sha256sum "$1" | awk '{print $1}')"
	elif have shasum; then
		actual="$(shasum -a 256 "$1" | awk '{print $1}')"
	else
		actual="$(openssl dgst -sha256 "$1" | awk '{print $NF}')"
	fi
	[ "$actual" = "$2" ]
}

# ------------------------------------------------------------------- jq -----

tool_install_jq() {
	local os arch asset url tmp sums expected
	os="$(detect_os)"
	arch="$(detect_arch)"
	case "$os" in
	darwin) asset="jq-macos-${arch}" ;;
	linux) asset="jq-linux-${arch}" ;;
	*) return 1 ;;
	esac
	url="https://github.com/jqlang/jq/releases/download/jq-${GHO_JQ_VERSION}"
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/gho-jq.XXXXXX")"
	log_info "downloading jq ${GHO_JQ_VERSION} (${asset})"
	_download "${url}/${asset}" "${tmp}/jq" || {
		rm -rf "$tmp"
		return 1
	}
	sums="${tmp}/sha256sum.txt"
	if _download "${url}/sha256sum.txt" "$sums"; then
		expected="$(grep -E "[[:space:]]\\*?${asset}\$" "$sums" | awk '{print $1}' | head -1)"
		if [ -n "$expected" ]; then
			_verify_sha256 "${tmp}/jq" "$expected" || {
				log_error "jq checksum mismatch — refusing to install"
				rm -rf "$tmp"
				return 1
			}
			log_info "jq checksum verified"
		else
			log_warn "no published checksum line for ${asset}; installing unverified"
		fi
	else
		log_warn "could not fetch jq checksums; installing unverified"
	fi
	chmod 755 "${tmp}/jq"
	mv -f "${tmp}/jq" "${GHO_TOOLS_DIR}/jq"
	rm -rf "$tmp"
	hash -r 2>/dev/null || true
}

# --------------------------------------------------------------- hcloud -----

tool_install_hcloud() {
	local os arch asset url tmp expected
	os="$(detect_os)"
	arch="$(detect_arch)"
	asset="hcloud-${os}-${arch}.tar.gz"
	url="https://github.com/hetznercloud/cli/releases/download/v${GHO_HCLOUD_VERSION}"
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/gho-hcloud.XXXXXX")"
	log_info "downloading hcloud CLI ${GHO_HCLOUD_VERSION} (${asset})"
	_download "${url}/${asset}" "${tmp}/${asset}" || {
		rm -rf "$tmp"
		return 1
	}
	if _download "${url}/checksums.txt" "${tmp}/checksums.txt"; then
		expected="$(grep -E "[[:space:]]\\*?${asset}\$" "${tmp}/checksums.txt" | awk '{print $1}' | head -1)"
		if [ -n "$expected" ]; then
			_verify_sha256 "${tmp}/${asset}" "$expected" || {
				log_error "hcloud checksum mismatch — refusing to install"
				rm -rf "$tmp"
				return 1
			}
			log_info "hcloud checksum verified"
		else
			log_warn "no published checksum line for ${asset}; installing unverified"
		fi
	else
		log_warn "could not fetch hcloud checksums; installing unverified"
	fi
	tar -xzf "${tmp}/${asset}" -C "$tmp" hcloud 2>/dev/null || tar -xzf "${tmp}/${asset}" -C "$tmp"
	[ -f "${tmp}/hcloud" ] || {
		rm -rf "$tmp"
		return 1
	}
	chmod 755 "${tmp}/hcloud"
	mv -f "${tmp}/hcloud" "${GHO_TOOLS_DIR}/hcloud"
	rm -rf "$tmp"
	hash -r 2>/dev/null || true
}

# ------------------------------------------------------------ tailscale -----

# The Tailscale CLI talks to a local daemon, so it cannot simply be dropped into
# .tools/bin — it has to come from a real installation. We look everywhere it
# realistically lives before asking for help.
tool_find_tailscale() {
	local c
	for c in \
		"${TAILSCALE_CLI:-}" \
		"$(command -v tailscale 2>/dev/null || true)" \
		/Applications/Tailscale.app/Contents/MacOS/Tailscale \
		/Applications/Tailscale.app/Contents/MacOS/tailscale \
		"$HOME/Applications/Tailscale.app/Contents/MacOS/Tailscale" \
		/usr/local/bin/tailscale \
		/usr/bin/tailscale \
		/opt/homebrew/bin/tailscale \
		/opt/tailscale/tailscale; do
		[ -n "$c" ] && [ -x "$c" ] && {
			printf '%s' "$c"
			return 0
		}
	done
	return 1
}

tool_install_tailscale() {
	local os
	os="$(detect_os)"
	if [ "$os" = "linux" ]; then
		log_info "installing Tailscale via the official installer (requires sudo)"
		curl -fsSL --proto '=https' https://tailscale.com/install.sh | sh || return 1
		sudo tailscale up >/dev/null 2>&1 || true
		return 0
	fi
	if have brew; then
		log_info "installing the Tailscale app via Homebrew"
		brew install --cask tailscale-app 2>/dev/null || brew install tailscale || return 1
		return 0
	fi
	return 1
}

# ----------------------------------------------------- generic requirement ---

# _pkg_install <package...> — best-effort system package installation.
_pkg_install() {
	if have apt-get; then
		sudo apt-get update -qq && sudo apt-get install -y -qq "$@"
	elif have dnf; then
		sudo dnf install -y "$@"
	elif have yum; then
		sudo yum install -y "$@"
	elif have pacman; then
		sudo pacman -Sy --noconfirm "$@"
	elif have apk; then
		sudo apk add --no-cache "$@"
	elif have brew; then
		brew install "$@"
	else
		return 1
	fi
}

# require_tool <command> <apt package> <human note>
require_tool() {
	local cmd="$1" pkg="$2" note_text="${3:-}"
	have "$cmd" && return 0
	log_warn "missing required tool: ${cmd}${note_text:+ (${note_text})}"
	if ask_yes_no "Install ${cmd} now?" y; then
		_pkg_install "$pkg" >/dev/null 2>&1 || true
		hash -r 2>/dev/null || true
	fi
	have "$cmd"
}
