for image in $(docker images --no-trunc --all --format "{{.Repository}}:{{.Tag}}" | grep oryxdevmcr.azurecr.io/public/oryx/)
do
docker tag $image ${image/oryxdevmcr.azurecr.io\/public\/oryx/mcr.microsoft.com\/oryx}-dummy
done