FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    subversion \
    libxml2-dev \
    libncurses5-dev \
    libsqlite3-dev \
    libssl-dev \
    libjansson-dev \
    libedit-dev \
    uuid-dev \
    pkg-config \
    libsrtp2-dev \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-20-current.tar.gz && \
    tar -zxvf asterisk-20-current.tar.gz && \
    cd asterisk-20.* && \
    ./contrib/scripts/get_mp3_source.sh || true && \
    ./configure --with-jansson-bundled && \
    make menuselect.makeopts && \
    menuselect/menuselect --enable format_mp3 menuselect.makeopts && \
    menuselect/menuselect --enable res_srtp menuselect.makeopts && \
    make -j$(nproc) && \
    make install && \
    make samples && \
    make config && \
    ldconfig

EXPOSE 5060/udp 5060/tcp 10000-20000/udp

CMD ["asterisk", "-f", "-vvvg"]
