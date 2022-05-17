FROM --platform=linux/amd64 ubuntu:20.04

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y wget tar git gzip unzip cmake software-properties-common curl
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc

ADD . /dasm
WORKDIR /dasm
RUN make -j8
