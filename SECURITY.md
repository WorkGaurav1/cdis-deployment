# Security Policy

Don't open a public GitHub issue for a security vulnerability. Email **gauravbisen999@gmail.com** with a description and, if possible, steps to reproduce.

This repo is exported from [CDIS Template](https://github.com/WorkGaurav1/cdis-engineering-template), which also covers `cdis-frontend` and `cdis-backend` — a vulnerability found here likely applies there too, worth mentioning in the report. Production secrets (`compose/.env.production`, DB passwords, JWT secrets) are never committed anywhere — if you find one that has been, that's a P0 report regardless of anything else.
