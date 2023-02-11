# WordPress Swarm Deployment

[![standard-readme compliant](https://img.shields.io/badge/standard--readme-OK-green.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme) [![Build Status](https://travis-ci.org/thomasvincent/wordpress-swarm.svg?branch=master)](https://travis-ci.org/thomasvincent/wordpress-swarm)

A Docker Swarm cluster deployment for running Wordpress using DNS name-based discovery.

## Features

- Five services running in a Docker Swarm cluster:
  - A Wordpress instance with labels for Traefik to load-balance
  - A MariaDB database configured for Galera-based clustering using Swarm mode DNS for discovery
  - A Traefik proxying and load balancing container 
  - A Redis instance for caching
  - An Nginx instance

## Deployment

To deploy, run the following command:
```docker stack deploy --compose-file docker-stack.yml wordpress```


## Scaling

To scale the Galera cluster to 3 nodes, run the following command:

```docker service scale wordpress=10```


## Cleanup

To shut down the services, run the following command:

```docker service rm wpcluster wordpress```


## Maintainers

[@thomasvincent](https://github.com/thomasvincent)

## Contribute

See [the contribute file](contribute.md) for more information. PRs accepted.

## License

Apache 2.0 License © 2017 Thomas Vincent
