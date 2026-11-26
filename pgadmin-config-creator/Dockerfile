FROM python:3.13-slim

WORKDIR /app
RUN useradd --user-group pgadmin-config-creator \
    && install -d -o pgadmin-config-creator -g pgadmin-config-creator /config
COPY app.py .
USER pgadmin-config-creator

CMD ["python", "app.py"]
