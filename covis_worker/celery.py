from __future__ import absolute_import, unicode_literals
from celery import Celery

from decouple import config

app = Celery('covis_worker',
             broker=config('CELERY_BROKER', default='amqp://user:bitnami@rabbitmq'),
             backend=config('CELERY_BACKEND', default='rpc://'),
             include=['covis_worker.postprocess', 'covis_worker.rezip'])

# Optional configuration, see the application user guide.
app.conf.update(
    result_expires=3600,
    concurrency=1,
    worker_prefetch_multiplier=1,
    task_acks_late=True,
    broker_connection_timeout=60,
    broker_heartbeat=300,
    task_send_sent_event=True,
    worker_send_task_events=True
)
app.conf.task_routes = {
       'covis_worker.postprocess.*' : {'queue': 'postprocess'},
       'covis_worker.rezip.*' : {'queue': 'rezip'}
}


if __name__ == '__main__':
    app.start()
