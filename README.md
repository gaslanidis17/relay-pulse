# Relay Pulse


A synthetic full-stack delivery operations analytics platform designed to demonstrate operational monitoring, diagnostic workflows, AI-assisted analysis, and scalable internal tooling.



> \*\*Portfolio note:\*\* This project is a fully synthetic reconstruction inspired by the types of operational problems I have worked on. All companies, locations, users, data, metrics, calculations, thresholds, and business rules shown in this repository are fictional.



\## Live Demo



Live deployment coming soon.



\[View Source Code](https://github.com/gaslanidis17/relay-pulse)



\## Overview



Relay Pulse brings multiple operational workflows into a single analytics environment.



The platform allows an operations team to:



\- monitor delivery performance across regions, countries, and cities

\- investigate delayed deliveries and operational bottlenecks

\- compare location and partner performance

\- review geographic delivery patterns

\- generate structured AI-assisted summaries

\- export operational views for stakeholder reporting

\- move from high-level KPIs to detailed root-cause investigation



The project was designed as an example of how fragmented operational data and manual investigations can be converted into a more scalable, self-service workflow.



\## The Problem



Operational teams often work across disconnected dashboards, spreadsheets, SQL queries, and manual reports.



This creates several problems:



\- investigations take too long

\- stakeholders depend on analysts for routine questions

\- metric definitions become inconsistent

\- important issues are identified too late

\- findings are difficult to communicate clearly

\- repeated analysis is not captured as a reusable workflow



Relay Pulse demonstrates a possible solution: one platform that connects monitoring, diagnostics, geographic analysis, and AI-assisted interpretation.



\## Key Features



\### Multi-level performance monitoring



Users can move between region, country, and city views while retaining a consistent analytical structure.



\### Delivery diagnostics



The platform provides focused views for:



\- delayed deliveries

\- delivery-time performance

\- courier-level performance

\- venue-level diagnostics

\- vehicle distribution

\- operational overlap patterns

\- geographic pickup and drop-off activity



\### AI-assisted summaries



AI functionality is used to transform structured operational data into concise summaries, highlighted findings, and recommended areas for investigation.



The AI layer supports the analyst rather than replacing the underlying metrics or decision-making process.



\### Synthetic data engine



The public version includes synthetic data generation so the application can demonstrate realistic operational workflows without exposing confidential information.



\### Export and stakeholder reporting



Users can export selected analytical views for further reporting and stakeholder communication.



\## Example Workflow



A typical investigation might look like this:



1\. Identify a market with deteriorating delivery-time performance.

2\. Compare the affected cities against regional benchmarks.

3\. Review hourly and daily trends.

4\. Inspect venue, courier, vehicle, and geographic patterns.

5\. Use the AI summary to structure the key findings.

6\. Export the analysis for stakeholder review.

7\. Monitor whether the selected operational intervention improved performance.



\## Architecture



```text

React + TypeScript frontend

&#x20;       |

&#x20;       | REST API

&#x20;       v

FastAPI backend

&#x20;       |

&#x20;       |-- Synthetic data engine

&#x20;       |-- Operational metric processing

&#x20;       |-- AI summary service

&#x20;       |-- Cache and refresh layer

&#x20;       |-- Optional Snowflake integration

