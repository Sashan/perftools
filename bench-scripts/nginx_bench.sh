#!/bin/ksh -x
#
# Copyright 2025 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the Apache License 2.0 (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html
#

#
#
# make sure to disable firewall
#	ufw disable
# it feels like ipv6 loopback traffic is disabled on ubunut
#
INSTALL_ROOT=${BENCH_INSTALL_ROOT:-"$HOME/work.openssl/bench.binaries"}
WORKSPACE_ROOT=${BENCH_WORKSPACE_ROOT:-"$HOME/work.openssl/bench.workspace"}
MAKE_OPTS=${BENCH_MAKE_OPTS}
HTTPS_PORT=${BENCH_HTTPS_PORT:-'4430'}
HTTP_PORT=${BENCH_HTTP_PORT:-'8080'}
CERT_SUBJ=${BENCH_CERT_SUBJ:-'/CN=localhost'}
CERT_ALT_SUBJ=${BENCH_CERT_ALT_SUBJ:-'subjectAltName=DNS:localhost,IP:127.0.0.1'}
APACHE_VERSION='2.4.65'

function check_env {
	if [[ ! -x "$(which git)" ]] ; then
		echo 'No git in PATH'
		exit 1
	fi

	if [[ ! -x `$(which cmake)` ]] ; then
		echo 'No cmake in PATH'
		exit 1
	fi

	if [[ ! -x "$(which wget)" ]] ; then
		echo 'No wget in PATH'
		exit 1
	fi

	if [[ ! -x "$(which openssl)" ]] ; then
		echo 'No openssl in PATH'
		exit 1
	fi

	if [[ ! -x "$(which autoconf)" ]] ; then
		echo 'No autoconf in PATH'
		exit 1
	fi

	if [[ ! -x "$(which automake)" ]] ; then
		echo 'No automake in PATH'
		exit 1
	fi

	if [[ ! -x "$(which seq)" ]] ; then
		echo 'No seq in PATH'
		exit 1
	fi

	TEST_FILE=".test_file.$$"
	mkdir -p "${WORKSPACE_ROOT}"
	if [[ $? -ne 0 ]] ; then
		echo "Can not create ${WORKSPACE_ROOT}"
		exit 1;
	fi
	touch "${WORKSPACE_ROOT}/${TEST_FILE}"
	if [[ $? -ne 0 ]] ; then
		echo "${WORKSPACE_ROOT} is not writable"
		exit 1
	fi

	mkdir -p "${INSTALL_ROOT}"
	if [[ $? -ne 0 ]] ; then
		echo "Can not create ${INSTALL_ROOT}"
		exit 1;
	fi
	touch "${INSTALL_ROOT}/${TEST_FILE}"
	if [[ $? -ne 0 ]] ; then
		echo "${INSTALL_ROOT} is not writable"
		exit 1
	fi

	rm -f "${INSTALL_ROOT}/${TEST_FILE}"
	rm -f "${WORKSPACE_ROOT}/${TEST_FILE}"
}

function cleanup {
	rm -rf ${INSTALL_ROOT}
	rm -rf ${WORKSPACE_ROOT}
}

function install_openssl {
	typeset OPENSSL_REPO='https://github.com/openssl/openssl'
	typeset BRANCH_NAME=$1
	typeset DIRNAME=''

	if [[ "${BRANCH_NAME}" = 'master' ]] ; then
		DIRNAME='openssl-master'
	else
		DIRNAME="${BRANCH_NAME}"
	fi

	cd ${WORKSPACE_ROOT}
	mkdir -p ${DIRNAME}
	cd ${DIRNAME}

	git clone --single-branch -b ${BRANCH_NAME} --depth 1 \
		https://github.com/openssl/openssl . || exit 1

	./Configure --prefix="${INSTALL_ROOT}/${DIRNAME}" \
		--libdir="${INSTALL_ROOT}/${DIRNAME}/lib" || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
	make clean || exit 1
}

function install_wolfssl {
	typeset VERSION=$1
	typeset WOLFSSL_TAG="v${VERSION}-stable"
	typeset WOLFSSL_WORKSPCE="${WORKSPACE_ROOT}/wolfssl"
	typeset WOLFSSL_REPO='https://github.com/wolfSSL/wolfssl'

	mkdir -p ${WOLFSSL_WORKSPCE}
	cd ${WOLFSSL_WORKSPCE}
	git clone "${WOLFSSL_REPO}" .
	if [[ $? -ne 0 ]] ; then
		#
		# make sure master is up-to date just in
		# case we build a master version
		#
		git checkout master || exit 1
		git pull --rebase || exit 1
	fi

	if [[ -n "${VERSION}" ]] ; then

		git branch -l | grep ${VERSION}
		if [[ $? -ne 0 ]] ; then
			git checkout tags/${WOLFSSL_TAG} -b wolfssl-${VERSION} || exit 1
		fi
	fi

	if [[ -z ${VERSION} ]] ; then
		VERSION='wolfssl-master'
	fi

	AUTOCONF_VERSION=2.72 AUTOMAKE_VERSION=1.16 ./autogen.sh || exit 1

	./configure --prefix="${INSTALL_ROOT}/wolfssl-${VERSION}" \
	    --enable-nginx || exit 1

	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
}

function install_libressl {
	typeset VERSION=${1:-4.1.0}
	typeset SUFFIX='tar.gz'
	typeset BASENAME='libressl'
	typeset DOWNLOAD_FILE="${BASENAME}-${VERSION}.${SUFFIX}"
	typeset BUILD_DIR="${BASENAME}-${VERSION}"
	typeset DOWNLOAD_URL='https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/'
	typeset DOWNLOAD_LINK="${DOWNLOAD_URL}/${DOWNLOAD_FILE}"

	cd "$WORKSPACE_ROOT"
	wget -O "$DOWNLOAD_FILE" "$DOWNLOAD_LINK" || exit 1
	tar xzf "${DOWNLOAD_FILE}"
	cd ${BUILD_DIR}
	./configure --prefix="${INSTALL_ROOT}/${BUILD_DIR}" || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
}

function install_boringssl {
	typeset BORING_REPO='https://boringssl.googlesource.com/boringssl'
	cd "${WORKSPACE_ROOT}"
	mkdir -p boringssl
	cd boringssl
	git clone "${BORING_REPO}" .
	cmake -B build -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}/boringssl" \
	    -DCMAKE_BUILD_TYPE=Release || exit 1
	cd build || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
	cd "${WORKSPACE_ROOT}"
}

function install_boringssl {
	typeset BORING_REPO='https://boringssl.googlesource.com/boringssl'
	typeset BORING_NAME='boringssl'
	cd "${WORKSPACE_ROOT}"
	mkdir -p "${BORING_NAME}"
	cd "${BORING_NAME}"
	git clone "${BORING_REPO}" . || exit 1
	cmake -B build -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}/${BORING_NAME}" \
	    -DCMAKE_BUILD_TYPE=Release || exit 1
	cd build || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
	cd "${WORKSPACE_ROOT}"
}

function install_aws_lc {
	typeset AWS_REPO='https://github.com/aws/aws-lc.git'
	typeset AWS_NAME="aws-lc"
	cd "${WORKSPACE_ROOT}"
	mkdir -p "${AWS_NAME}"
	cd "${AWS_NAME}"
	git clone "${AWS_REPO}" . || exit 1
	cmake -B build -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}/boringssl" \
	    -DCMAKE_BUILD_TYPE=Release || exit 1
	cd build || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
	cd "${WORKSPACE_ROOT}"
}

function install_nginx {
	typeset SSL_LIB=$1
	typeset NGIX_REPO='https://github.com/nginx/nginx'
	typeset VERSION='1.28'
	typeset BASENAME='nginx'
	if [[ -z "${VERSION}" ]] ; then
		VERSION='master'
	fi
	typeset DIRNAME="${BASENAME}-${VERSION}"

	if [[ -z "${SSL_LIB}" ]] ; then
		SSL_LIB='openssl-master'
	fi

	cd "${WORKSPACE_ROOT}"
	mkdir -p "${DIRNAME}"
	cd "${DIRNAME}"
	git clone "${NGIX_REPO}" . || exit 1
	if [[ -n "${VERSION}" ]] ; then
		git checkout -b stable-${VERSION} origin/stable-${VERSION} || exit 1
	fi

	#
	# note ngix unlike apache requires pointer to ssl sources
	#
	./auto/configure --prefix="${INSTALL_ROOT}/${SSL_LIB}" \
		--with-http_ssl_module \
		--with-openssl="${WORKSPACE_ROOT}/${SSL_LIB}" || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
	cd "${WORKSPACE_ROOT}"
}

function install_wolf_nginx {
	typeset SSL_LIB=$1
	typeset NGIX_REPO='https://github.com/nginx/nginx'
	typeset VERSION='1.25'
	typeset BASENAME='nginx'
	if [[ -z "${VERSION}" ]] ; then
		VERSION='master'
	fi
	typeset DIRNAME="${BASENAME}-${VERSION}"

	if [[ -z "${SSL_LIB}" ]] ; then
		SSL_LIB='openssl-master'
	fi

	cd "${WORKSPACE_ROOT}"
	mkdir -p "${DIRNAME}"
	cd "${DIRNAME}"
	git clone "${NGIX_REPO}" . || exit 1
	if [[ -n "${VERSION}" ]] ; then
		git checkout -b stable-${VERSION} origin/stable-${VERSION} || exit 1
	fi

	cd "${WORKSPACE_ROOT}"
	git clone https://github.com/wolfssl/wolfssl-nginx || exit 1
	cd "${DIRNAME}"
	patch -p1 < ../wolfssl-ngix/nginx-${VERSION}.0-wolfssl.patch || exit 1

	#
	# note ngix unlike apache requires pointer to ssl sources
	#
	./auto/configure --prefix="${INSTALL_ROOT}/${SSL_LIB}" \
		--with-http_ssl_module \
		--with-wolfssl="${WORKSPACE_ROOT}/${SSL_LIB}" || exit 1
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
	cd "${WORKSPACE_ROOT}"
}

function install_siege {
	typeset VERSION='4.1.7'
	typeset SUFFIX='tar.gz'
	typeset BASENAME='siege'
	typeset DOWNLOAD_FILE="${BASENAME}-${VERSION}.${SUFFIX}"
	typeset BUILD_DIR="${BASENAME}-${VERSION}"
	typeset DOWNLOAD_URL='http://download.joedog.org/siege/'
	typeset DOWNLOAD_LINK="${DOWNLOAD_URL}/${DOWNLOAD_FILE}"
	typeset SSL_LIB=$1

	if [[ -z "${SSL_LIB}" ]] ; then
		SSL_LIB='openssl-master'
	fi

	cd "$WORKSPACE_ROOT"
	wget -O "$DOWNLOAD_FILE" "$DOWNLOAD_LINK" || exit 1
	tar xzf "${DOWNLOAD_FILE}"
	cd ${BUILD_DIR}
	./configure --prefix="${INSTALL_ROOT}/${SSL_LIB}" \
		--with-ssl=${SSL_LIB}
	make ${MAKE_OPTS} || exit 1
	make ${MAKE_OPTS} install || exit 1
}

function run_test {
	typeset SSL_LIB=$1
	typeset i=0
	if [[ -z "${SSL_LIB}" ]] ; then
		SSL_LIB='openssl-master'
	fi
	typeset SIEGE="${INSTALL_ROOT}"/openssl-master/bin/siege
	typeset HTDOCS="${INSTALL_ROOT}/${SSL_LIB}"/htdocs

	#
	# we always try to use siege from openssl master by default,
	# if not found then we try the one which is installed for
	# openssl version we'd like to test.
	#
	if [[ ! -x "{SIEGE}" ]] ; then
		SIEGE="${INSTALL_ROOT}/${SSL_LIB}"/bin/siege
	fi

	if [[ ! -x "${SIEGE}" ]] ; then
		echo "no siege found in ${SIEGE}"
		exit 1
	fi

	rm -f siege_urls.txt
	for i in `ls -1 ${HTDOCS}/*.txt` ; do
		echo "https://localhost:${HTTPS_PORT}/`basename $i`" >> siege_urls.txt
	done

	"${INSTALL_ROOT}/${SSL_LIB}/bin/httpd"
	if [[ $? -ne 0 ]] ; then
		echo "could not start ${INSTALL_ROOT}/${SSL_LIB}/bin/httpd"
		exit 1
	fi
	"${SIEGE}" -t 5M -b -f siege_urls.txt 2> "${INSTALL_ROOT}/${SSL_LIB}.txt"
	rm siege_urls.txt
	$("${INSTALL_ROOT}/${SSL_LIB}/bin/apachectl" stop) || exit 1
}

function setup_tests {
#	install_openssl master
#	install_nginx
#	install_siege
#
#	cd "${WORKSPACE_ROOT}"
#	# cleanup workspace as checkout to branch may fail,
#	# also make clean is not enough.
#	rm -rf *
#
#	for i in 3.0 3.1 3.2 3.3 3.4 3.5 ; do
#		install_openssl openssl-$i
#		install_nginx
#		install_siege openssl-$i
#		cd "${WORKSPACE_ROOT}"
#		rm -rf *
#	done

	install_wolfssl 5.8.2
	install_nginx wolfssl-5.8.2
#	cd "${WORKSPACE_ROOT}"
#	rm -rf *

#	install_libressl 4.1.0
#	install_siege libressl-4.1.0
#	install_nginx libressl-4.1.0
#	cd "${WORKSPACE_ROOT}"
#	rm -rf *
#
#	install_boringssl
#	install_siege boringssl
#	install_nginx boringssl
#	cd "${WORKSPACE_ROOT}"
#	rm -rf *
#
#	install_aws_lc
#	install_nginx aws-lc
#	install_siege aws-lc
#	cd "${WORKSPACE_ROOT}"
#	rm -rf *
}

function run_tests {
	for i in 3.0 3.1 3.2 3.3 3.4 3.5 ; do
		run_test openssl-${i}
	done
	run_test openssl-master
	run_test libressl-4.1.0
	#
	# could not get apache with wolfssl working
	#
	#run_test wolfssl-5.8.2
	run_test boringssl
	run_test aws-lc
}

setup_tests
#run_tests
#
#echo 'testing using siege is complete, results can be foun dhere:'
#ls -1 "${INSTALL_ROOT}/*.txt"
