for image in $(docker images --no-trunc --all --format "{{.Repository}}:{{.Tag}}" | grep wawsimages.azurecr.io/)
do
docker tag $image ${image/wawsimages.azurecr.io/sbussaTest.azurecr.io}
docker push ${image/wawsimages.azurecr.io/sbussaTest.azurecr.io}
done