FROM openjdk:8-jre-alpine

ENV RUN_USER java-runner
ENV RUN_GROUP ${RUN_USER}
ENV RUN_DIR /var/empty/${RUN_USER}
ENV PATH $PATH:${RUN_DIR}
ENV ARGS ""

ENV JMX_REMOTE_PORT=${JMX_REMOTE_PORT:-22222}
ENV JMX_REMOTE_RMI_PORT=${JMX_REMOTE_RMI_PORT:-22223}
ENV JMX_REMOTE_SSL=${JMX_REMOTE_SSL:-false}

#java-container instead of localhost etc if JMX is called from other container:
ENV JAVA_RMI_SERVER_HOSTNAME=${JAVA_RMI_SERVER_HOSTNAME:-localhost}

RUN mkdir -p ${RUN_DIR}
RUN /usr/sbin/addgroup ${RUN_GROUP} && /usr/sbin/adduser -h /var/empty/${RUN_USER} -s /sbin/nologin -D -H ${RUN_USER} -G ${RUN_GROUP} -g "User running the Java process"
RUN chown ${RUN_USER}:${RUN_GROUP} /var/log
RUN echo ${IMAGE_VERSION} > ${RUN_DIR}/as.image.version

RUN printf "monitorRole alpha123!\ncontrolRole alpha123!\n" > ${RUN_DIR}/jmxremote.password
WORKDIR ${RUN_DIR}
RUN chmod 400 jmxremote.password && chown ${RUN_USER}:${RUN_USER} jmxremote.password

RUN printf "#!/bin/sh\nexec java \${JAVA_OPTIONS} -Dcom.sun.management.jmxremote.password.file=jmxremote.password -Dcom.sun.management.jmxremote.port=\${JMX_REMOTE_PORT} -Dcom.sun.management.jmxremote.rmi.port=\${JMX_REMOTE_RMI_PORT} -Dcom.sun.management.jmxremote.ssl=\${JMX_REMOTE_SSL} -Djava.rmi.server.hostname=\${JAVA_RMI_SERVER_HOSTNAME} -jar *.jar \${ARGS}\n" > entrypoint.sh && chmod 755 entrypoint.sh

ARG JAR
# Replace the 'target/' with the path to you jar file, don't replace the ${JAR} with jar file name, it will be done at time of build
COPY ${JAR} .
USER ${RUN_USER}
#ONBUILD COPY *.jar .
#USER ${RUN_USER}
ENTRYPOINT [ "entrypoint.sh" ]

