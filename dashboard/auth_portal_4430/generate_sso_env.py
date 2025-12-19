#!/usr/bin/env python3
"""
SSO 환경변수 생성 스크립트
YAML 설정 파일에서 SSO 설정을 읽어 .env 파일을 생성합니다.

사용법:
    python generate_sso_env.py --config /path/to/cluster.yaml
    python generate_sso_env.py --config /path/to/cluster.yaml --output .env.production
"""

import argparse
import json
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)


def load_yaml_config(config_path: str) -> dict:
    """YAML 설정 파일 로드"""
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def generate_sso_env(config: dict, include_secrets: bool = True) -> str:
    """
    SSO 설정에서 .env 파일 내용 생성

    Args:
        config: YAML 설정 딕셔너리
        include_secrets: 시크릿 포함 여부

    Returns:
        .env 파일 내용 문자열
    """
    sso = config.get('sso', {})

    lines = [
        "# ============================================================================",
        "# Auth Portal SSO Configuration",
        "# Generated from YAML cluster configuration",
        "# ============================================================================",
        "",
        "# Flask Configuration",
        f"FLASK_DEBUG={'True' if config.get('environment', {}).get('debug', False) else 'False'}",
        f"SECRET_KEY={config.get('environment', {}).get('secret_key', 'change-this-secret-key-in-production')}",
        "",
        "# JWT Configuration",
        f"JWT_SECRET_KEY={config.get('environment', {}).get('jwt_secret_key', 'change-this-jwt-secret-in-production')}",
        "JWT_ALGORITHM=HS256",
        f"JWT_EXPIRATION_HOURS={config.get('environment', {}).get('jwt_expiration_hours', 8)}",
        "",
        "# Redis Configuration",
        f"REDIS_HOST={config.get('redis', {}).get('host', 'localhost')}",
        f"REDIS_PORT={config.get('redis', {}).get('port', 6379)}",
        f"REDIS_DB={config.get('redis', {}).get('db', 0)}",
    ]

    # Redis password
    redis_password = config.get('redis', {}).get('password', '')
    if include_secrets and redis_password:
        lines.append(f"REDIS_PASSWORD={redis_password}")
    else:
        lines.append("REDIS_PASSWORD=")

    lines.extend([
        "",
        "# ============================================================================",
        "# SSO Configuration",
        "# ============================================================================",
        f"SSO_ENABLED={'true' if sso.get('enabled', False) else 'false'}",
        f"SSO_TYPE={sso.get('type', 'saml')}",
        "",
    ])

    # SAML Configuration
    saml = sso.get('saml', {})
    lines.extend([
        "# SAML Configuration",
        f"SAML_IDP_METADATA_URL={saml.get('idp_metadata_url', '')}",
        f"SAML_SP_ENTITY_ID={saml.get('sp', {}).get('entity_id', 'hpc-dashboard')}",
    ])

    # SAML IdP individual settings
    idp = saml.get('idp', {})
    if idp:
        lines.extend([
            f"SAML_IDP_ENTITY_ID={idp.get('entity_id', '')}",
            f"SAML_IDP_SSO_URL={idp.get('sso_url', '')}",
            f"SAML_IDP_SLO_URL={idp.get('slo_url', '')}",
        ])

        # Handle certificate (could be inline or file path)
        cert = idp.get('certificate', '')
        cert_file = idp.get('certificate_file', '')
        if cert_file:
            lines.append(f"# SAML IdP Certificate file: {cert_file}")
            lines.append(f"SAML_IDP_CERTIFICATE_FILE={cert_file}")
        elif cert and include_secrets:
            # For inline certificate, escape newlines
            cert_escaped = cert.replace('\n', '\\n')
            lines.append(f"SAML_IDP_CERTIFICATE={cert_escaped}")

    # Get dashboard URLs for SAML ACS/SLS
    dashboard = config.get('dashboard', {})
    base_url = dashboard.get('base_url', 'http://localhost')
    auth_port = 4430

    lines.extend([
        f"SAML_ACS_URL={base_url}:{auth_port}/auth/saml/acs",
        f"SAML_SLS_URL={base_url}:{auth_port}/auth/saml/sls",
        "",
    ])

    # OIDC Configuration
    oidc = sso.get('oidc', {})
    lines.extend([
        "# OIDC Configuration",
        f"OIDC_ISSUER={oidc.get('issuer', '')}",
        f"OIDC_CLIENT_ID={oidc.get('client_id', '')}",
    ])

    if include_secrets:
        lines.append(f"OIDC_CLIENT_SECRET={oidc.get('client_secret', '')}")
    else:
        lines.append("OIDC_CLIENT_SECRET=")

    # OIDC scopes
    scopes = oidc.get('scopes', ['openid', 'profile', 'email', 'groups'])
    if isinstance(scopes, list):
        scopes_str = ','.join(scopes)
    else:
        scopes_str = scopes
    lines.append(f"OIDC_SCOPES={scopes_str}")

    # OIDC requested claims (SAML의 AttributeConsumingService와 유사)
    # OIDC는 scope로 클레임을 요청하지만, claims 파라미터로 명시적 요청도 가능
    requested_claims = oidc.get('requested_claims', [])
    if isinstance(requested_claims, list) and requested_claims:
        claims_str = ','.join(requested_claims)
        lines.append(f"OIDC_REQUESTED_CLAIMS={claims_str}")
    else:
        lines.append("# OIDC_REQUESTED_CLAIMS=  # (비워두면 attribute_mapping에서 자동 생성)")

    lines.append("")

    # Attribute Mapping (as JSON)
    attr_mapping = sso.get('attribute_mapping', {
        'username': 'uid',
        'email': 'email',
        'groups': 'groups',
        'display_name': 'displayName',
        'department': 'department'
    })
    lines.extend([
        "# SSO Attribute Mapping (JSON format)",
        f"SSO_ATTRIBUTE_MAPPING='{json.dumps(attr_mapping)}'",
        "",
    ])

    # Group Permissions (as JSON)
    group_permissions = sso.get('group_permissions', {
        'HPC-Admins': ['dashboard', 'cae', 'vnc', 'app', 'admin'],
        'DX-Users': ['dashboard', 'vnc', 'app'],
        'CAEG-Users': ['dashboard', 'cae', 'vnc', 'app']
    })
    lines.extend([
        "# Group Permissions Mapping (JSON format)",
        f"SSO_GROUP_PERMISSIONS='{json.dumps(group_permissions)}'",
        "",
    ])

    # Service URLs
    lines.extend([
        "# ============================================================================",
        "# Service URLs (Nginx reverse proxy paths)",
        "# ============================================================================",
        f"DASHBOARD_URL={dashboard.get('dashboard_path', '/dashboard')}",
        f"CAE_URL={dashboard.get('cae_path', '/cae')}",
        f"VNC_URL={dashboard.get('vnc_path', '/vnc')}",
        f"APP_URL={dashboard.get('app_path', '/app')}",
        "",
        "# Server",
        "HOST=0.0.0.0",
        f"PORT={auth_port}",
    ])

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Generate .env file from YAML SSO configuration',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate .env from cluster YAML
  python generate_sso_env.py --config /path/to/my_multihead_cluster.yaml

  # Generate to specific output file
  python generate_sso_env.py --config cluster.yaml --output .env.production

  # Generate without secrets (for version control)
  python generate_sso_env.py --config cluster.yaml --no-secrets --output .env.example
        """
    )

    parser.add_argument(
        '--config', '-c',
        required=True,
        help='Path to YAML configuration file'
    )

    parser.add_argument(
        '--output', '-o',
        default='.env',
        help='Output .env file path (default: .env)'
    )

    parser.add_argument(
        '--no-secrets',
        action='store_true',
        help='Do not include secrets in output (for .env.example)'
    )

    parser.add_argument(
        '--print',
        action='store_true',
        dest='print_only',
        help='Print to stdout instead of writing to file'
    )

    parser.add_argument(
        '--force', '-f',
        action='store_true',
        help='Overwrite existing file without prompt'
    )

    args = parser.parse_args()

    # Validate config file exists
    config_path = Path(args.config)
    if not config_path.exists():
        print(f"Error: Configuration file not found: {config_path}")
        sys.exit(1)

    try:
        # Load YAML config
        print(f"Loading configuration from: {config_path}")
        config = load_yaml_config(config_path)

        # Check if SSO section exists
        if 'sso' not in config:
            print("Warning: 'sso' section not found in configuration.")
            print("Using default SSO configuration (SSO disabled, mock mode)")

        # Generate .env content
        env_content = generate_sso_env(config, include_secrets=not args.no_secrets)

        if args.print_only:
            print("\n" + "=" * 60)
            print(env_content)
            print("=" * 60)
        else:
            output_path = Path(args.output)

            # Check if file exists
            if output_path.exists() and not args.force:
                response = input(f"File {output_path} already exists. Overwrite? [y/N]: ")
                if response.lower() != 'y':
                    print("Aborted.")
                    sys.exit(0)

            # Write .env file
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(env_content)

            print(f"Successfully generated: {output_path}")

            # Set file permissions (readable only by owner)
            os.chmod(output_path, 0o600)
            print(f"File permissions set to 600 (owner read/write only)")

            # Print summary
            sso = config.get('sso', {})
            print(f"\nSSO Configuration Summary:")
            print(f"  - SSO Enabled: {sso.get('enabled', False)}")
            print(f"  - SSO Type: {sso.get('type', 'saml')}")

            if sso.get('type') == 'saml':
                saml = sso.get('saml', {})
                print(f"  - SAML IdP Metadata URL: {saml.get('idp_metadata_url', '(not set)')}")
                print(f"  - SAML SP Entity ID: {saml.get('sp', {}).get('entity_id', 'hpc-dashboard')}")
            elif sso.get('type') == 'oidc':
                oidc = sso.get('oidc', {})
                print(f"  - OIDC Issuer: {oidc.get('issuer', '(not set)')}")
                print(f"  - OIDC Client ID: {oidc.get('client_id', '(not set)')}")

            group_perms = sso.get('group_permissions', {})
            print(f"  - Group Permission Mappings: {len(group_perms)} groups")
            for group_name in group_perms:
                print(f"      - {group_name}: {group_perms[group_name]}")

        return 0

    except yaml.YAMLError as e:
        print(f"Error parsing YAML: {e}")
        return 1
    except Exception as e:
        print(f"Error: {e}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
