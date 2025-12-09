#!/usr/bin/env python3
"""
Auto-Inventory Bot - Kubernetes Infrastructure Documentation Generator
Scans nodes and applications, generates Obsidian-compatible Markdown files.
"""

import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import yaml
from kubernetes import client, config
from kubernetes.client.rest import ApiException


class InventoryBot:
    def __init__(self, output_dir: str = "/workspace/docs"):
        """Initialize the inventory bot with Kubernetes client."""
        self.output_dir = Path(output_dir)
        self.v1 = None
        self.net_v1 = None
        self._setup_k8s_client()

    def _setup_k8s_client(self):
        """Setup Kubernetes client with fallback authentication."""
        kubeconfig_path = os.getenv('KUBECONFIG_PATH')

        if kubeconfig_path:
            # Remote cluster access via kubeconfig file
            try:
                config.load_kube_config(config_file=kubeconfig_path)
                print(f"✓ Loaded kubeconfig from {kubeconfig_path}")
            except config.ConfigException as e:
                print(f"✗ Failed to load kubeconfig from {kubeconfig_path}: {e}")
                sys.exit(1)
        else:
            # In-cluster or local kubeconfig
            try:
                config.load_incluster_config()
                print("✓ Loaded in-cluster Kubernetes configuration")
            except config.ConfigException:
                try:
                    config.load_kube_config()
                    print("✓ Loaded kubeconfig from local environment")
                except config.ConfigException as e:
                    print(f"✗ Failed to load Kubernetes configuration: {e}")
                    sys.exit(1)

        self.v1 = client.CoreV1Api()
        self.net_v1 = client.NetworkingV1Api()

    def _write_markdown(self, filepath: Path, frontmatter: Dict, content: str = ""):
        """Write a Markdown file with YAML frontmatter."""
        filepath.parent.mkdir(parents=True, exist_ok=True)

        with open(filepath, 'w') as f:
            f.write("---\n")
            yaml.dump(frontmatter, f, default_flow_style=False, sort_keys=False)
            f.write("---\n\n")
            f.write(content)

        print(f"  → Written: {filepath.relative_to(self.output_dir)}")

    def scan_nodes(self):
        """Scan all Kubernetes nodes and generate hardware documentation."""
        print("\n📦 Scanning Kubernetes Nodes...")

        try:
            nodes = self.v1.list_node()
        except ApiException as e:
            print(f"✗ Failed to list nodes: {e}")
            return

        hardware_dir = self.output_dir / "Hardware"

        for node in nodes.items:
            hostname = node.metadata.name
            status = node.status

            # Extract node information
            internal_ip = next(
                (addr.address for addr in status.addresses if addr.type == "InternalIP"),
                "N/A"
            )

            os_image = status.node_info.os_image
            kernel_version = status.node_info.kernel_version
            container_runtime = status.node_info.container_runtime_version

            cpu_capacity = status.capacity.get('cpu', 'N/A')
            memory_capacity = status.capacity.get('memory', 'N/A')

            # Determine node status
            node_ready = "Unknown"
            for condition in status.conditions:
                if condition.type == "Ready":
                    node_ready = "Ready" if condition.status == "True" else "NotReady"
                    break

            # Create frontmatter
            frontmatter = {
                'type': 'hardware',
                'hostname': hostname,
                'ip': internal_ip,
                'status': node_ready,
                'cpu_cores': cpu_capacity,
                'memory': memory_capacity,
                'os': os_image,
                'kernel': kernel_version,
                'updated': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
            }

            # Create content
            content = f"# {hostname}\n\n"
            content += f"**Physical Server:** `{hostname}`\n\n"
            content += f"## System Information\n\n"
            content += f"- **Internal IP:** {internal_ip}\n"
            content += f"- **Status:** {node_ready}\n"
            content += f"- **OS:** {os_image}\n"
            content += f"- **Kernel:** {kernel_version}\n"
            content += f"- **Container Runtime:** {container_runtime}\n\n"
            content += f"## Resources\n\n"
            content += f"- **CPU Cores:** {cpu_capacity}\n"
            content += f"- **Memory:** {memory_capacity}\n\n"
            content += f"## Labels\n\n"

            for key, value in node.metadata.labels.items():
                content += f"- `{key}`: {value}\n"

            # Write file
            filepath = hardware_dir / f"{hostname}.md"
            self._write_markdown(filepath, frontmatter, content)

        print(f"✓ Scanned {len(nodes.items)} nodes")

    def _get_pod_node(self, namespace: str, selector: Optional[Dict[str, str]]) -> str:
        """Get the node where pods matching the selector are running."""
        if not selector:
            return "N/A"

        try:
            label_selector = ",".join([f"{k}={v}" for k, v in selector.items()])
            pods = self.v1.list_namespaced_pod(
                namespace=namespace,
                label_selector=label_selector
            )

            if pods.items:
                # Get the first running pod's node
                for pod in pods.items:
                    if pod.spec.node_name:
                        return pod.spec.node_name
                return "N/A"
            else:
                return "N/A"
        except ApiException:
            return "N/A"

    def scan_applications(self):
        """Scan all Ingresses and generate application documentation."""
        print("\n🌐 Scanning Applications via Ingresses...")

        try:
            ingresses = self.net_v1.list_ingress_for_all_namespaces()
        except ApiException as e:
            print(f"✗ Failed to list ingresses: {e}")
            return

        apps_dir = self.output_dir / "Applications"
        app_count = 0

        for ingress in ingresses.items:
            app_name = ingress.metadata.name
            namespace = ingress.metadata.namespace

            # Extract URLs/hosts
            hosts = []
            if ingress.spec.rules:
                for rule in ingress.spec.rules:
                    if rule.host:
                        hosts.append(rule.host)

            primary_url = hosts[0] if hosts else "N/A"

            # Find which node the pods are running on
            # Try to find backend service and its pods
            hosted_on = "N/A"
            service_name = None

            if ingress.spec.rules and ingress.spec.rules[0].http:
                paths = ingress.spec.rules[0].http.paths
                if paths and paths[0].backend:
                    if hasattr(paths[0].backend, 'service') and paths[0].backend.service:
                        service_name = paths[0].backend.service.name

            if service_name:
                try:
                    service = self.v1.read_namespaced_service(service_name, namespace)
                    if service.spec.selector:
                        hosted_on = self._get_pod_node(namespace, service.spec.selector)
                except ApiException:
                    pass

            # Create frontmatter
            frontmatter = {
                'type': 'application',
                'name': app_name,
                'namespace': namespace,
                'url': primary_url,
                'hosted_on': hosted_on,
                'updated': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
            }

            # Create content with wiki-style links
            content = f"# {app_name}\n\n"
            content += f"**Application deployed in namespace:** `{namespace}`\n\n"
            content += f"## Access\n\n"

            if hosts:
                content += f"**Primary URL:** [{primary_url}](https://{primary_url})\n\n"
                if len(hosts) > 1:
                    content += f"**Additional URLs:**\n"
                    for host in hosts[1:]:
                        content += f"- [{host}](https://{host})\n"
                    content += "\n"

            content += f"## Infrastructure\n\n"
            content += f"- **Namespace:** `{namespace}`\n"

            if hosted_on != "N/A":
                content += f"- **Hosted On:** [[{hosted_on}]]\n"
            else:
                content += f"- **Hosted On:** Unknown\n"

            if service_name:
                content += f"- **Service:** `{service_name}`\n"

            content += f"\n## Ingress Configuration\n\n"
            content += f"- **Ingress Name:** `{app_name}`\n"
            content += f"- **Ingress Class:** {ingress.spec.ingress_class_name or 'default'}\n"

            # Add annotations if present
            if ingress.metadata.annotations:
                content += f"\n### Annotations\n\n"
                for key, value in ingress.metadata.annotations.items():
                    content += f"- `{key}`: {value}\n"

            # Write file
            filepath = apps_dir / f"{app_name}.md"
            self._write_markdown(filepath, frontmatter, content)
            app_count += 1

        print(f"✓ Scanned {app_count} applications")

    def run(self):
        """Execute the full inventory scan."""
        print("=" * 60)
        print("🤖 Auto-Inventory Bot - Starting Infrastructure Scan")
        print("=" * 60)

        self.scan_nodes()
        self.scan_applications()

        print("\n" + "=" * 60)
        print("✅ Inventory scan completed successfully!")
        print(f"📁 Output directory: {self.output_dir}")
        print("=" * 60)


if __name__ == "__main__":
    output_dir = os.getenv('OUTPUT_DIR', '/workspace/docs')
    bot = InventoryBot(output_dir=output_dir)
    bot.run()
