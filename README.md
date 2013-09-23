# MongoDB deployment for BOSH

This MongsDB deployment is intended for use with
[BOSH](https://github.com/cloudfoundry/bosh) deployment. Using this
you can easily create and scale your MongoDB cluster

## How to use it

1. For start you should install BOSH. You can find examples
[here](http://docs.cloudfoundry.com/docs/running/deploying-cf/). For
use this method you don't need to install CloudFoundry, you just need
small part of CloudFoundry (message bus).

2. Create manifest for your MongoDB cluster. You can find example in
`examples` subdirectory.

3. Compile this release. You can do this using `bosh create release
--force`

4. Upload release to BOSH. You can do this using `bosh upload release`

5. Deploy cluser using manifest:
   a. `bosh deployment <your deployment file>` - selects deployment
   file to upload
   b. `bosh deploy` - applies deployment manifest to cluster.
6. When it finish installation, you can check nodes addresses using
`bosh vms`


## Collaborate

You are welcome to contribute via
[pull request](https://help.github.com/articles/using-pull-requests).
