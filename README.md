# WordPress Swarm Deployment

[![standard-readme compliant](https://img.shields.io/badge/standard--readme-OK-green.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme) [![Build Status](https://travis-ci.org/thomasvincent/wordpress-swarm.svg?branch=master)](https://travis-ci.org/thomasvincent/wordpress-swarm)

A Docker Swarm cluster deployment for running WordPress using DNS name-based discovery.

## Features

- Five services running in a Docker Swarm cluster:
  - A WordPress instance with labels for Traefik to load-balance
  - A MariaDB database configured for Galera-based clustering using Swarm mode DNS for discovery
  - A Traefik proxying and load balancing container
  - A Redis instance for caching
  - An Nginx instance

## Requirements

- Docker Engine 20.10.0 or later
- Docker Compose 1.29.0 or later
- Docker Swarm mode enabled

## Deployment

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/wordpress-swarm.git
   ```

2. `cd wordpress-swarm`

3. Deploy the WordPress stack:bash
   `docker stack deploy -c docker-compose.yml wordpress` 
5. Access the WordPress site: Open your browser and visit http://wordpress.example.com. Replace wordpress.example.com with your actual domain name.

## Scaling
To scale the WordPress service to 10 replicas, run the following command:

`docker service scale wordpress_wordpress=10`
## Monitoring
Access the Traefik dashboard by visiting http://traefik.example.com. Replace traefik.example.com with your actual domain name.

## Cleanup
To shut down and remove the WordPress stack, run the following command:

`docker stack rm wordpress`

## Contributing
Contributions are welcome! Please see the ~[contribute.md](contribute.md)~ file for more information.

## Maintainers
* ~[Your Name](https://github.com/yourusername)~

##License
This project is licensed under the Apache 2.0 License. See the ~[LICENSE](LICENSE)~ file for more information.
