FROM python:2.7-alpine
RUN pip install flask && \
    pip install flask_restful
RUN mkdir helloWorld
COPY helloWorld/ helloWorld/
CMD ["python","helloWorld/main.py"]
