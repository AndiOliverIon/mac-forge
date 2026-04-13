#!/usr/bin/env python3
import socket
import sys

def send_wol(mac_address, ip_address, port):
    # Format MAC address
    add_octets = mac_address.replace(':', '').replace('-', '')
    if len(add_octets) != 12:
        print(f"Invalid MAC address: {mac_address}")
        return
    
    # Create magic packet
    msg = bytes.fromhex('FF' * 6 + add_octets * 16)
    
    # Send packet
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        print(f"Sending Magic Packet to {mac_address} via {ip_address}:{port}...")
        s.sendto(msg, (ip_address, port))

if __name__ == "__main__":
    target_mac = "E8:9C:25:38:4C:63"
    # Try multiple targets to overcome routing/ARP issues
    targets = [
        "192.168.100.46",    # Direct IP (works only if ARP exists)
        "192.168.100.255",   # Subnet Directed Broadcast (best if allowed)
        "255.255.255.255",   # Global Broadcast (worst for routing but broad)
        "192.168.68.255",    # Source Subnet Broadcast (in case it bridges)
        "192.168.255.255"    # Wide Broadcast
    ]
    
    for target in targets:
        send_wol(target_mac, target, 7)
        send_wol(target_mac, target, 9)
