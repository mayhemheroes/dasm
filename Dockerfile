FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc

ADD . /dasm
WORKDIR /dasm
RUN make -j8

RUN mkdir -p /deps
RUN ldd /dasm/bin/dasm | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /dasm/bin/dasm /dasm/bin/dasm
ENV LD_LIBRARY_PATH=/deps
