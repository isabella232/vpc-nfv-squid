# Virtual Network Functions, VNF, using VPC Routing and Squid

VPC Routing allows more control over network flow.  It can be used to support a Virtual Network Function, VNF.  Off the shelf firewall instances like those from Palo Alto and F5,  can be added to a VPC and traffic routes adjusted to insert additional layers of security.


This post will demonstrate a Squid VNF.  Quote from the site:


> Squid is a caching proxy for the Web supporting HTTP, HTTPS, FTP, and more. It reduces bandwidth and improves response times by caching and reusing frequently-requested web pages:


![architecture](./images/architecture.png)

