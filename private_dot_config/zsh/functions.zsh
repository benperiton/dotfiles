# Reset docker: stop/remove all containers, images, volumes, and networks
function reset-docker() {
    docker stop $(docker ps -a -q) 2>/dev/null
    docker rm -f $(docker ps -a -q) 2>/dev/null
    docker rmi -f $(docker images -a -q) 2>/dev/null
    docker volume rm -f $(docker volume ls -q) 2>/dev/null
    docker network rm $(docker network ls -q) 2>/dev/null
    echo "Docker reset complete"
}
