<h3 align="center">PinnedImageSet testing</h3>

<div align="left">

[![Status](https://img.shields.io/badge/status-active-success.svg)]() [![GitHub Issues](https://img.shields.io/github/issues/cloud-bulldozer/pinned-images-testing.svg)](https://github.com/cloud-bulldozer/pinned-images-testing/issues) [![GitHub Pull Requests](https://img.shields.io/github/issues-pr/cloud-bulldozer/pinned-images-testing.svg)](https://github.com/kcloud-bulldozer/pinned-images-testing/pulls) [![License](https://img.shields.io/badge/license-apache%202.0-blue.svg)](/LICENSE)

</div>

---

<p align="center"> Scripts and steps to ease PinnedImageSet feature
    <br> 
</p>

## Table of Contents

- [About](#about)
- [Getting Started](#getting_started)
- [Folder Structure](#folder_structure)
- [Prerequisites](#prerequisites)
- [Running](#running)
- [Check the feature](#check_feature)
- [Upgrade](#upgrade)

## About <a name = "about"></a>

The PinnedImageSet feature main focus is to make upgrade process faster, by pre-downloading images to the nodes.

To test what the impact on the process is we need to run a set of steps to meassure it. To automate most of the steps this repo contains a set of scripts that can make it easier and faster.

## Getting Started <a name = "getting_started"></a>

Clone this repo:

`git clone git@github.com:cloud-bulldozer/pinned-images-testing.git`

### Folder structure <a name = "folder_structure"></a>

#### root

Here you will find basic information to the repository and the main scripts that we run to obtain data and results.

- [pinned.sh](./pinned.sh) Applies PinnedImageSet feature to the cluster
- [upgrade.sh](./upgrade.sh) Applies upgrade to the cluster 
- [transition-time.sh](./transition-time.sh) Display the `PinnedImageSetsProgressing` for each node
- [featuregate.yaml](./featuregate.yaml) CRD to enable gated features.
- [infra.mcp.yaml](./infra.mcp.yaml) CRD to create the Infra nodes MachinCOpnfigPool.
- [featuregate.yaml](./featuregate.yaml) CRD to enable gated features.

#### templates

- [pinned-images.yaml.template](pinned-images.yaml.template) Template that is used to generate the PinnedImageSet CRD.

#### processed

Files will be generated into this folder.

- [check_images.sh](check_images.sh) Script that can be used to check if the images have been downloaded on each node

#### PinnedImages

Jupyter Notebook used to help with the creation of the graphs.

#### example

- [machineconfignode.infra.example.yaml](./machineconfignode.infra.example.yaml) CRD example file for machineconfignode for an Infra node 

#### extras

Bits of code or small bash scripts to help out, not completelly related to the test

### Prerequisites <a name = "prerequisites"></a>

Have an OpenShift cluster created in AWS.

The scritps will assume that the KUBECONFIG env var is set.

### Running <a name = "running"></a>

A step by step of how to run it:

First go to `pinned.sh` and be sure to modify the versions that you want

```
export ocp_version_channel=${OCP_VERSION_CHANNEL:-candidate}
export ocp_version="4.17"
export rel=4.17.0-rc.2
```

When you run the script, it will do the following steps

- Do an `oc adm release extract` of this version `$rel`
- Install `dittybopper` on the cluster
- Lift Cluster protections and enable Gated Features
- Generate the `PinnedImagesSet` CRD and the `images.txt` in the `processed` folder
- Apply the PinnedImageSet CRD, print the start date, and wait for it to finish.


### Check the feature <a name = "check_feature"></a>

After the `pinned.sh` script is finished, you can check transition timmings for each node running the `transition-time.sh` script.

You can also go into each node and use the `check_images.sh` script to see if all images where pulled and the logs for the pulled images.

> Be sure to update the `check_images.sh` script and put the list of images in the `images.txt` file to the placehodler in the script.


### Upgrade <a name = "upgrade"></a>

When you have checked what you need to know of your cluster, you can go ahead and run the `upgrade.sh` script. This is based on the ROSA upgrade sccript, and should print out the timmings of the Upgrade.

> Check the versions on that script

```
export ocp_version_channel=${OCP_VERSION_CHANNEL:-candidate}
export ocp_version="4.17"
export VERSION="4.17.0-rc.2"
```




