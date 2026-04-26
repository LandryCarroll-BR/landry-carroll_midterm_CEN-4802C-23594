# syntax=docker/dockerfile:1

# --- Build stage ---
FROM eclipse-temurin:17-jdk AS build
WORKDIR /workspace

# Copy Maven wrapper + pom first to leverage Docker cache
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw

# Download dependencies (cached layer)
RUN ./mvnw -B -DskipTests dependency:go-offline

# Copy source and build
COPY src src
RUN ./mvnw -B -DskipTests package

# --- Runtime stage ---
FROM eclipse-temurin:17-jre
WORKDIR /app

# Install the Datadog Java tracer into the runtime image.
ADD https://dtdg.co/latest-java-tracer /opt/dd-java-agent.jar

# Copy the built jar from the build stage
COPY --from=build /workspace/target/*.jar app.jar

ENV DD_TRACE_ENABLED=false

EXPOSE 8080
ENTRYPOINT ["java","-javaagent:/opt/dd-java-agent.jar","-jar","/app/app.jar"]
