#!/usr/bin/env python3
"""
Test Slurm Integration for App Sessions
"""

import sys
import os

# Add current directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from services.slurm_app_manager import SlurmAppManager
import time

def test_slurm_integration():
    """Test Slurm job submission for gedit app"""

    print("=== Testing Slurm App Manager ===\n")

    # Create manager
    manager = SlurmAppManager()

    # Test session details
    session_id = "test-session-001"
    app_id = "gedit"
    vnc_port = 6080

    print(f"Session ID: {session_id}")
    print(f"App ID: {app_id}")
    print(f"VNC Port: {vnc_port}")
    print()

    # Submit job
    print("Submitting Slurm job...")
    try:
        job_info = manager.submit_app_job(
            session_id=session_id,
            app_id=app_id,
            vnc_port=vnc_port
        )

        print(f"✅ Job submitted successfully!")
        print(f"   Job ID: {job_info['job_id']}")
        print(f"   Status: {job_info['status']}")
        print()

        # Wait for job to start running
        print("Waiting for job to start (max 30 seconds)...")
        for i in range(30):
            time.sleep(1)

            status_info = manager.get_job_status_info(session_id)
            if status_info:
                print(f"   [{i+1}s] Status: {status_info['status']}", end="")
                if status_info['status'] == 'RUNNING':
                    print(f" on node {status_info.get('node', 'unknown')}")
                    print(f"\n✅ Job is RUNNING!")
                    print(f"   Node: {status_info.get('node')}")
                    print(f"   Node IP: {status_info.get('node_ip')}")
                    print(f"   VNC URL: ws://{status_info.get('node_ip')}:{vnc_port}")
                    break
                else:
                    print()
        else:
            print(f"\n⚠️  Job did not reach RUNNING state in 30 seconds")
            print(f"   Final status: {status_info.get('status') if status_info else 'UNKNOWN'}")

        print()

        # Cancel job
        print("Cancelling job...")
        if manager.cancel_job(session_id):
            print("✅ Job cancelled successfully")
        else:
            print("❌ Failed to cancel job")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

    print("\n=== Test Complete ===")
    return True


if __name__ == "__main__":
    success = test_slurm_integration()
    sys.exit(0 if success else 1)
