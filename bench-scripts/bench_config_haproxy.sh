#!/usr/bin/env ksh
#
# Copyright 2025 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the Apache License 2.0 (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html
#

set -x

INSTALL_ROOT=${BENCH_INSTALL_ROOT:-"/tmp/bench.binaries"}
RESULT_DIR=${BENCH_RESULTS:-"${INSTALL_ROOT}/results"}
WORKSPACE_ROOT=${BENCH_WORKSPACE_ROOT:-"/tmp/bench.workspace"}
MAKE_OPTS=${BENCH_MAKE_OPTS}
HAPROXY_BUILD_TARG=${BENCH_HAPROXY_BUILD_TARG:-'linux-glibc'}
CERT_SUBJ=${BENCH_CERT_SUBJ:-'/CN=localhost'}
CERT_ALT_SUBJ=${BENCH_CERT_ALT_SUBJ:-'subjectAltName=DNS:localhost,IP:127.0.0.1'}
HOST=${BENCH_HOST:-'127.0.0.1'}
PORT_RSA_REUSE=${BENCH_PORT_RSA_REUSE:-7000}
PORT_RSA=${BENCH_PORT_RSA:-7100}
PORT_EC_REUSE=${BENCH_PORT_EC_REUSE:-7200}
PORT_EC=${BENCH_PORT_EC:-7300}
HAPROXY_VERSION='v3.2.0'
CERT_SUBJ=${BENCH_CERT_SUBJ:-'/CN=localhost'}
CERT_ALT_SUBJ=${BENCH_CERT_ALT_SUBJ:-'subjectAltName=DNS:localhost,IP:127.0.0.1'}
HOST=${BENCH_HOST:-'127.0.0.1'}

function install_httpterm {
    typeset SSL_LIB=$1
    #
    # FixMe: with https://github.com/wtarreau/httpterm,
    # once https://github.com/wtarreau/httpterm/pull/1
    # will be merged
    #
    typeset HTTPTERM_REPO="https://github.com/sashan/httpterm"
    typeset BASENAME='h1load'
    typeset DIRNAME="${BASENAME}"
    typeset SSL_CFLAGS=''
    typeset SSL_LFLAGS=''

    if [[ -z "${SSL_LIB}" ]] ; then
        SSL_LIB="openssl-master"
    fi

    git clone -b fix.null-deref "${HTTPTERM_REPO}" "${DIRNAME}" || exit 1
    cd ${DIRNAME} || exit 1
    make || exit 1
    install httpterm "${INSTALL_ROOT}/${SSL_LIB}/bin/httpterm" || exit 1
    cd "${WORKSPACE_ROOT}"
}

function install_h1load {
    typeset SSL_LIB=$1
    typeset H1LOAD_REPO="https://github.com/wtarreau/h1load"
    typeset BASENAME='h1load'
    typeset DIRNAME="${BASENAME}"
    typeset SSL_CFLAGS=''
    typeset SSL_LFLAGS=''

    if [[ -z "${SSL_LIB}" ]] ; then
        SSL_LIB="openssl-master"
    fi

    echo $SSL_LIB | grep 'woflssl' > /dev/null
    if [[ $? -eq 0 ]] ; then
        #
        # adjust flags for wolfssl
    #
    SSL_CFLAGS="-I${INSTALL_ROOT}/${SSL_LIB}/include"
    SSL_CFLAGS="${SSL_CFLAGS} -include ${INSTALL_ROOT}/${SSL_LIB}/include/wolfssl/options.h"
    SSL_LFLAGS="${INSTALL_ROOT}/${SSL_LIB}/lib -lwfolfssl -Wl,-rpath=${INSTALL_ROOT}/lib"
    else
    SSL_CFLAGS="-I${INSTALL_ROOT}/${SSL_LIB}/include"
    SSL_LFLAGS="${INSTALL_ROOT}/${SSL_LIB}/lib -lssl -lcrypto"
    fi
    git clone "${H1LOAD_REPO}" "${DIRNAME}" || exit 1
    cd ${DIRNAME} || exit 1
    make || exit 1
    install h1load "${INSTALL_ROOT}/${SSL_LIB}/bin/h1load" || exit 1
    cd scripts
    for i in *.sh ; do
    install $i "${INSTALL_ROOT}/${SSL_LIB}/bin/$i" || exit 1
    done
    cd "${WORKSPACE_ROOT}"
}

function install_haproxy {
    typeset SSL_LIB=$1
    typeset VERSION=${HAPROXY_VERSION:-v3.2.0}
    typeset HAPROXY_REPO="https://github.com/haproxy/haproxy.git"
    typeset BASENAME='haproxy'
    typeset DIRNAME="${BASENAME}-${VERSION}"

    if [[ -z "${SSL_LIB}" ]] ; then
        SSL_LIB="openssl-master"
    fi

    if [[ -f "${INSTALL_ROOT}/${SSL_LIB}/sbin/haproxy" ]] ; then
        echo "haproxy already installed; skipping.."
    else
        cd "${WORKSPACE_ROOT}"
        mkdir -p "${DIRNAME}" || exit 1
        cd "${DIRNAME}"
        git clone "${HAPROXY_REPO}" -b ${VERSION} --depth 1 . || exit 1
        
        # haproxy does not have a configure script; only a big makefile
        make clean
        make ${MAKE_OPTS} \
             TARGET=${HAPROXY_BUILD_TARG} \
             USE_OPENSSL=1 \
             USE_OPENSSL=USE_QUIC \
             SSL_INC="${INSTALL_ROOT}/${SSL_LIB}/include" \
             SSL_LIB="${INSTALL_ROOT}/${SSL_LIB}/lib" || exit 1

        make install ${MAKE_OPTS} \
             PREFIX="${INSTALL_ROOT}/${SSL_LIB}" || exit 1
    fi

    cd ${WORKSPACE_ROOT}
}

#
# function creates haproxy.conf which ishould be
# identical to configuration used here [1].
#
# The configuration file defines 4 proxy variants:
#   ssl-reause with rsa+dh certificate,
#       https client connects to port 7020
#
#   no-ssl-reuse, with rsa+dh certificate,
#       https client connects to port 7120
#
#   ssl-reuse with ecdsa-256 certificate,
#       https client connects to port 7220
#
#   no-ssl-reuse with ecdsa-256 certificate,
#       https client connects to port 7320
#
# [1] https://www.haproxy.com/blog/state-of-ssl-stacks
#   search for 'daisy-chain'
#
function config_haproxy {
    typeset SSL_LIB=$1
    typeset RSACERTKEY=''
    typeset HAPROXY_CONF='haproxy.conf'
    typeset BASEPORT=''
    typeset TOPPORT=''
    typeset PORT=''
    typeset SSL_REUSE=''

    if [[ -z "${SSL_LIB}" ]] ; then
        SSL_LIB'=master'
    fi

    HAPROXY_CONF=${INSTALL_ROOT}/${SSL_LIB}/${HAPROXY_CONF}

cat <<EOF > ${HAPROXY_CONF}
global
	default-path config
	tune.listener.default-shards by-thread
	tune.idle-pool.shared off
	ssl-default-bind-options ssl-min-ver TLSv1.3 ssl-max-ver TLSv1.3
	ssl-server-verify none

EOF

    for BASEPORT in ${PORT_RSA_REUSE} ${PORT_RSA} ${PORT_EC_REUSE} ${PORT_EC} ; do
cat <<EOF >> ${HAPROXY_CONF}
defaults ssl-reuse
	mode http
	http-reuse never
	default-server max-reuse 0 ssl ssl-min-ver TLSv1.3 ssl-max-ver TLSv1.3
	option httpclose
	timeout client 10s
	timeout server 10s
	timeout connect 10s

frontend port${BASENAME}
	bind :${BASEPORT} ssl crt ${PROXYCERT}
	http-request return status 200 content-type "text/plain" string "it works"

EOF
        BASEPORT=$(( ${BASEPORT} + 1))
        TOPPORT=$(( ${BASEPORT} + 20))
        if [[ ${BASEPORT} -eq ${PORT_RSA_REUSE} || ${BASEPORT} -eq ${PORT_EC_REUSE} ]] ; then
            SSL_REUSE='no-ssl-reuse'
        else
            SSL_REUSE=''
        fi
        for PORT in $(seq ${BASEPORT} ${TOPPORT}) ; do
cat <<EOF >> ${HAPROXY_CONF}
listen port${PORT}
	bind :${PORT} ssl crt ${PROXYCERT} ${SSL_REUSE}
	server next ${HOST}:$(( ${PORT} - 1))

EOF
        done
    done
}
