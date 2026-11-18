# Образ участника для заочного этапа Hackathon Go1 (задание T1).
# Требования ТЗ 3.1: linux/amd64, Ubuntu 22.04 LTS (Jammy), ROS 2 Humble,
# Eclipse Cyclone DDS / rmw_cyclonedds_cpp, только CPU, без прав root,
# без интернета во время испытаний.
#
# База ros:humble-ros-base — это Ubuntu 22.04 + ROS 2 Humble + colcon/rosdep,
# поэтому не нужно вручную подключать packages.ros.org и ловить сборочные
# сюрпризы. Всё нужное рантайму ставится здесь; в рантайме сети нет.

FROM ros:humble-ros-base

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ROS_DISTRO=humble \
    ROS_VERSION=2

# Cyclone DDS как RMW по требованию ТЗ. Конфиг DDS и ROS_DOMAIN_ID приходят
# из лаунчера организаторов (RMW_IMPLEMENTATION / CYCLONEDDS_URI), поэтому
# в образе только сам RMW-пакет — свои жёсткие настройки не прописываем.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ros-humble-rmw-cyclonedds-cpp \
        ca-certificates \
        coreutils \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Проверка на этапе сборки: пакеты на месте (упасть на сборке лучше, чем молча
# получить неработающий RMW на испытаниях).
RUN test -f /opt/ros/humble/setup.bash \
 && dpkg -s ros-humble-rmw-cyclonedds-cpp >/dev/null \
 && ls /opt/ros/humble/lib/librmw_cyclonedds_cpp.so >/dev/null

# Запуск без прав root: отдельный непривилегированный пользователь.
RUN groupadd --gid 10001 participant \
 && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash participant

# Контракт запуска: исполняемый /entrypoint.sh в корне файловой системы.
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh && chown root:root /entrypoint.sh

USER participant
WORKDIR /home/participant

# Judge всё равно переопределяет entrypoint явным --entrypoint /entrypoint.sh,
# но значение по умолчанию должно быть таким же, чтобы образ вёл себя
# одинаково при ручном docker run.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ping"]
