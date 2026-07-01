FROM --platform=linux/amd64 xuxueli/xxl-job-admin:3.4.2 AS extract

FROM eclipse-temurin:17-jre

ENV PARAMS="" \
    TZ=PRC

COPY --from=extract /app.jar /app.jar

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:8080/ || exit 1

ENTRYPOINT ["sh", "-c", "java ${LOG_HOME:+-DLOG_HOME=$LOG_HOME} -jar $JAVA_OPTS /app.jar $PARAMS"]
