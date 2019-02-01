#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/TCPPacket.h"
#include <Timer.h>

module TransportP{
	
	uses interface Timer<TMilli> as beaconTimer;
	uses interface Timer<TMilli> as packetTimer;

	uses interface SimpleSend as Sender;
	uses interface Forwarder;


	uses interface List<socket_t> as SocketList;
	uses interface Queue<pack> as packetQueue;

	provides interface Transport;
}
implementation{

	//command void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

	socket_t getSocket(uint8_t destPort, uint8_t srcPort);
	bool isInList(uint8_t destPort, uint8_t srcPort);


	event void packetTimer.fired(){
		pack myMsg; 
		tcp_pack* myTCPPack;
		socket_t mySocket;
		uint16_t size = call SocketList.size();

		if(!call packetQueue.empty()){
			myMsg = call packetQueue.head();
			myTCPPack = (tcp_pack*)(myMsg.payload);
			
			if(isInList(myTCPPack->destPort, myTCPPack->srcPort) == TRUE){
				mySocket = getSocket(myTCPPack->destPort, myTCPPack->srcPort);

				if(mySocket.lastAck < myTCPPack->ACK && mySocket.lastWritten > myTCPPack->ACK){
					call packetQueue.enqueue(myMsg);
					call Sender.send(myMsg, mySocket.dest.addr);
					dbg(TRANSPORT_CHANNEL, "Resending packet\n");

				}else if (mySocket.lastAck < myTCPPack->ACK && mySocket.lastWritten < myTCPPack->ACK && mySocket.lastWritten < mySocket.lastAck){
					
					call packetQueue.enqueue(myMsg);
					call Sender.send(myMsg, mySocket.dest.addr);
					dbg(TRANSPORT_CHANNEL, "Resending packet\n");

				}else if (mySocket.lastAck > myTCPPack->ACK && mySocket.lastWritten > myTCPPack->ACK){

					call packetQueue.enqueue(myMsg);
					call Sender.send(myMsg, mySocket.dest.addr);
					dbg(TRANSPORT_CHANNEL, "Resending packet\n");
				}

			}else{
			}
		}

		if (!call packetQueue.empty() && !call packetTimer.isRunning()){
			call packetTimer.startOneShot(100000);
		}
	}

	bool isInList(uint8_t destPort, uint8_t srcPort){
		socket_t mySocket;
		uint32_t i = 0;
		uint32_t size = call SocketList.size();
		
		for (i = 0; i < size; i++){
			mySocket = call SocketList.get(i);
			if(mySocket.dest.port == srcPort && mySocket.src.port == destPort){
				return TRUE;
			}
		}

		//if server
		if(srcPort == -999){
			for (i = 0; i < size; i++){
				mySocket = call SocketList.get(i);
				if(mySocket.src.port == destPort && mySocket.state == LISTEN){
					return TRUE;
				}
			}
		}
		return FALSE;
	}
	
		

	socket_t getSocket(uint8_t destPort, uint8_t srcPort){
		socket_t mySocket;
		uint32_t i = 0;
		uint32_t size = call SocketList.size();
		
		for (i = 0; i < size; i++){
			mySocket = call SocketList.get(i);
			if(mySocket.dest.port == srcPort && mySocket.src.port == destPort){
				return mySocket;
			}
		}

		//if server
		if(srcPort == -999){
			for (i = 0; i < size; i++){
				mySocket = call SocketList.get(i);
				if(mySocket.src.port == destPort && mySocket.state == LISTEN){
					return mySocket;
				}
			}
		}
	}

	event void beaconTimer.fired(){
		uint32_t i = 0;
		bool isWrap;
		uint16_t size = call SocketList.size();
		socket_t mySocket;
		pack myMsg;
		tcp_pack* myTCPPack;

		for(i = 0; i < size; i++){
			mySocket = call SocketList.get(i);

			if(mySocket.state == LISTEN){
				continue;
			}
			if(mySocket.state == ESTABLISHED){
				
				if(mySocket.lastWritten - mySocket.lastSent != 0){
					
					if(mySocket.lastSent - mySocket.lastAck < mySocket.effectiveWindow){
						
						myTCPPack = (tcp_pack*)(myMsg.payload);
						myTCPPack->destPort = mySocket.dest.port;
						myTCPPack->srcPort = mySocket.src.port;
						myTCPPack->seq = mySocket.lastAck;
						myTCPPack->ACK = mySocket.lastAck;
						myTCPPack->flags = DATA_FLAG;
		
						if(mySocket.lastRead <= mySocket.lastRcvd){
						
							myTCPPack->window = mySocket.lastRead - mySocket.lastRcvd;
						}else{
							
							myTCPPack->window = mySocket.lastRead - mySocket.lastRcvd;
			
						}


						if(mySocket.lastSent + TCP_PACKET_MAX_PAYLOAD_SIZE > SOCKET_BUFFER_SIZE){
							isWrap = TRUE;
							memcpy(myTCPPack->payload, mySocket.sendBuff + mySocket.lastSent, mySocket.lastSent + TCP_PACKET_MAX_PAYLOAD_SIZE - SOCKET_BUFFER_SIZE);
							memcpy(myTCPPack->payload, mySocket.sendBuff, TCP_PACKET_MAX_PAYLOAD_SIZE - mySocket.lastSent + TCP_PACKET_MAX_PAYLOAD_SIZE - SOCKET_BUFFER_SIZE);
							mySocket.lastSent = TCP_PACKET_MAX_PAYLOAD_SIZE - mySocket.lastSent + TCP_PACKET_MAX_PAYLOAD_SIZE - SOCKET_BUFFER_SIZE;
						}else{
		
							isWrap = FALSE;
							memcpy(myTCPPack->payload, mySocket.sendBuff + mySocket.lastSent, TCP_PACKET_MAX_PAYLOAD_SIZE);
							mySocket.lastSent += TCP_PACKET_MAX_PAYLOAD_SIZE;
						}

						if(mySocket.lastSent > SOCKET_BUFFER_SIZE){
							mySocket.lastSent -= SOCKET_BUFFER_SIZE;

						}
	
						call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, 0);

						call packetQueue.enqueue(myMsg);
						if(!call packetTimer.isRunning()){
							call packetTimer.startOneShot(100000);
						}
				
						call Sender.send(myMsg, mySocket.dest.addr);
						mySocket.lastAck++;
					}
				}

			}else if (mySocket.state == SYN_SENT){
				
				myTCPPack->destPort = mySocket.dest.port;
				myTCPPack->srcPort = mySocket.src.port;
				myTCPPack->seq = 10;
				myTCPPack->ACK = 0;
				myTCPPack->flags = SYN_FLAG;
				myTCPPack->window = SOCKET_BUFFER_SIZE;
				
				call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, 0);
				call Sender.send(myMsg, mySocket.dest.addr);
			}else{
				call Transport.close(mySocket);
			}
		}
			
	}

	/*event void packetTimer.fired(){
		pack myMsg = call packetQueue.head();
		pack sendMsg;

		//cast as a tcp_pack
		tcp_pack* myTCPPack = (tcp_pack *)(myMsg.payload);
		socket_t mySocket = getSocket(myTCPPack->srcPort, myTCPPack->destPort);
		
		if(mySocket.dest.port){
			call SocketList.pushback(mySocket);

			//have to cast it as a uint8_t* pointer

			call Transport.makePack(&sendMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
			call Sender.send(sendMsg, mySocket.dest.addr);
		}
	

	}*/

	command socket_t Transport.socket(){
		uint16_t i = 0;
		socket_t mySocket;

		mySocket.lastWritten = 0;
		mySocket.lastAck = 0;
		mySocket.lastSent = 0;
		mySocket.lastRead = 0;
		mySocket.lastRcvd = 0;
		mySocket.nextExpected = 0;
		mySocket.effectiveWindow = 0;
		mySocket.state = CLOSED;
		
		dbg(TRANSPORT_CHANNEL, "Socket Set.\n");

		
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++){
			mySocket.rcvdBuff[i] = 0;
			mySocket.sendBuff[i] = 0;
		}

		if(!call beaconTimer.isRunning()){
			call beaconTimer.startPeriodic(100000);
		}
		
		call packetTimer.startOneShot(105000);

		dbg(TRANSPORT_CHANNEL, "Socket Given\n");

		return mySocket;

}

	command error_t Transport.bind(socket_t fd, socket_addr_t * addr){


		fd.src.addr = addr->addr;
		fd.src.port = addr->port;

		fd.state = LISTEN;

		call SocketList.pushback(fd);
		dbg(TRANSPORT_CHANNEL, "Binding socket\n");
		/*
		//not used, directly assign directly
		socket_t mySocket;
	
		mySocket.src.port = addr->port;
		mySocket.src.addr = addr->addr;
		mySocket.dest.port = addr->port;
		mySocket.dest.addr = addr->addr;*/
		
				
}

	command socket_t Transport.accept(socket_t fd){

		uint16_t i = 0;
		socket_t mySocket;
		//socket_t tempSocket;
		uint16_t size = call SocketList.size();
		//uint16_t i = 0;
		
		for(i = 0; i < size; i++){
			mySocket = call SocketList.get(i);
			if(fd.dest.addr == mySocket.dest.addr && fd.src.addr == mySocket.src.addr && fd.dest.port == mySocket.dest.port && fd.state == mySocket.state){
				return mySocket;
			}
		}
		
		call SocketList.pushback(fd);
		
}
	command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
		uint16_t temp;
		socket_t mySocket = fd;
		uint16_t writeLength;
		uint16_t key;
		bool isWrap;

		//mySocket = getSocket(mySocket.dest.port, mySocket.src.port);
		key = call Transport.getKey(fd.src.port, fd.dest.port, fd.dest.addr);

		if(call socketHash.contains(key)){
			mySocket = call socketHash.get(myKey);
		}else{
			return;
		}

		if(mySocket.lastWritten >= mySocket.lastAck){
			isWrap = TRUE;
			writeLength = (SOCKET_BUFFER_SIZE - mySocket.lastWritten) + mySocket.lastAck;
		}else{
			isWrap = FALSE;
			writeLength = (mySocket.lastAck - mySocket.lastWritten);
		}

		if (bufflen > writeLength){
			return 0;
		} else {
			if(isWrap == TRUE){
				temp = SOCKET_BUFFER_SIZE - mySocket.lastWritten;
		
				if(bufflen > temp){
					memcpy(mySocket.sendBuff + mySocket.lastWritten, buff, temp*sizeof(uint8_t));
					memcpy(mySocket.sendBuff, (buff + temp), (bufflen - temp)*sizeof(uint8_t));
				}else{
					memcpy(mySocket.sendBuff + mySocket.lastWritten, buff, bufflen*sizeof(uint8_t));

				}
	
				if(writeLength < (SOCKET_BUFFER_SIZE - mySocket.lastWritten) || bufflen < temp){
					mySocket.lastWritten += bufflen;
				}else{
					mySocket.lastWritten = bufflen - temp;
				}
			}else{
				memcpy(mySocket.sendBuff + mySocket.lastWritten, buff, bufflen*sizeof(uint8_t));
				mySocket.lastWritten += bufflen;
			}

			if(mySocket.lastWritten > SOCKET_BUFFER_SIZE){
				mySocket.lastWritten -= SOCKET_BUFFER_SIZE;

			}
			return bufflen;
		}
}
	command error_t Transport.receive(pack* package){

		uint8_t srcPort = 0;
		uint8_t destPort = 0;
		uint8_t seq = 0;
		uint8_t lastAck = 0;
		uint8_t flags = 0;
		uint16_t bufflen = TCP_PACKET_MAX_PAYLOAD_SIZE;
		uint16_t i = 0;
		uint16_t j = 0;
		socket_t mySocket;
		tcp_pack* msg = (tcp_pack *)(package->payload);


		pack myMsg;
		tcp_pack* myTCPPack;

		srcPort = msg->srcPort;
		destPort = msg->destPort;
		seq = msg->seq;
		lastAck = msg->ACK;
		flags = msg->flags;

		if(flags == SYN_FLAG || flags == SYN_ACK_FLAG || flags == ACK_FLAG){

			if(flags == SYN_FLAG){

				mySocket = getSocket(destPort, -999);
				if(mySocket.state == LISTEN){
					mySocket.state = SYN_RCVD;
					mySocket.dest.port = srcPort;
					mySocket.dest.addr = package->src;
					call SocketList.pushback(mySocket);
				
					myTCPPack = (tcp_pack *)(myMsg.payload);
					myTCPPack->destPort = mySocket.dest.port;
					myTCPPack->srcPort = mySocket.src.port;
					myTCPPack->seq = 1;
					myTCPPack->ACK = seq + 1;
					myTCPPack->flags = SYN_ACK_FLAG;
			
					call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
					call Sender.send(myMsg, mySocket.dest.addr);
				}
			}

			if(flags == SYN_ACK_FLAG){

				mySocket = getSocket(destPort, srcPort);
				mySocket.state = ESTABLISHED;
				call SocketList.pushback(mySocket);

				myTCPPack = (tcp_pack*)(myMsg.payload);
				myTCPPack->destPort = mySocket.dest.port;
				myTCPPack->srcPort = mySocket.src.port;
				myTCPPack->seq = 1;
				myTCPPack->ACK = seq + 1;
				myTCPPack->flags = ACK_FLAG;
			
				call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(myMsg, mySocket.dest.addr);

				//NEW TCPPack

				myTCPPack = (tcp_pack*)(myMsg.payload);
				myTCPPack->flags = DATA_FLAG;
				myTCPPack->destPort = mySocket.dest.port;
				myTCPPack->srcPort = mySocket.src.port;
				myTCPPack->seq = 0;
				
				//sends integers in accending order
				i = 0;
				while(i <= mySocket.effectiveWindow && i <= TCP_PACKET_MAX_PAYLOAD_SIZE - 1){
					myTCPPack->payload[i] = i;
					i++;
				}
				
				myTCPPack->ACK = i;
				call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
			
				call packetQueue.enqueue(myMsg);

				call Sender.send(myMsg, mySocket.dest.addr);
			}

			if(flags == ACK_FLAG){
				mySocket = getSocket(destPort, srcPort);
				if(mySocket.state == SYN_RCVD){
					mySocket.state = ESTABLISHED;
					call SocketList.pushback(mySocket);
				}
			}
		}

		if(flags == DATA_FLAG || flags == DATA_ACK_FLAG){

			if(flags == DATA_FLAG){
				
				mySocket = getSocket(destPort, srcPort);
				if(mySocket.state == ESTABLISHED){
					myTCPPack = (tcp_pack*)(myMsg.payload);
					if(msg->payload[0] != 0){
						i = mySocket.lastRcvd + 1;
						j = 0;
						while(j < msg->ACK){
							mySocket.rcvdBuff[i] = msg->payload[j];
							mySocket.lastRcvd = msg->payload[j];
							i++;
							j++;
						}
					}else{
						i = 0;
						while(i < msg->ACK){
							mySocket.rcvdBuff[i] = msg->payload[i];
							mySocket.lastRcvd = msg->payload[i];
							i++;
						}
					}

				mySocket.effectiveWindow = SOCKET_BUFFER_SIZE - mySocket.lastRcvd + 1;
				call SocketList.pushback(mySocket);
			
				myTCPPack->destPort = mySocket.dest.port;
				myTCPPack->srcPort = mySocket.src.port;
				myTCPPack->seq = seq;
				myTCPPack->ACK = seq + 1;
				myTCPPack->lastACK = mySocket.lastRcvd;
				myTCPPack->window = mySocket.effectiveWindow;
				myTCPPack->flags = DATA_ACK_FLAG;
				call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0 , myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(myMsg, mySocket.dest.addr);
				}
			
			} else if (flags == DATA_ACK_FLAG){
				mySocket = getSocket(destPort, srcPort);
				if(mySocket.state == ESTABLISHED){
					if(msg->window != 0 && msg->lastACK != mySocket.effectiveWindow){
						myTCPPack = (tcp_pack*)(myMsg.payload);
						i = msg->lastACK + 1;
						j = 0;
						
						while(j < msg->window && j < TCP_PACKET_MAX_PAYLOAD_SIZE && i <= mySocket.effectiveWindow){
							myTCPPack->payload[j] = i;
							i++;
							j++;
						}
					
						call SocketList.pushback(mySocket);
						myTCPPack->flags = DATA_FLAG;
						myTCPPack->destPort = mySocket.dest.port;
						myTCPPack->srcPort = mySocket.src.port;
						myTCPPack->ACK = i - 1 - msg->lastACK;
						myTCPPack->seq = lastAck;
						call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
	
						//call Sender. send(myMsg, mySocket.dest.addr);
	
	
						call packetQueue.dequeue();
						call packetQueue.enqueue(myMsg);
	
						call Sender.send(myMsg, mySocket.dest.addr);
					}else{

						mySocket.state = FIN_FLAG;
						call SocketList.pushback(mySocket);
						myTCPPack = (tcp_pack*)(myMsg.payload);
						myTCPPack->destPort = mySocket.dest.port;
						myTCPPack->srcPort = mySocket.src.port;
						myTCPPack->seq = 1;
						myTCPPack->ACK = seq + 1;
						myTCPPack->flags = FIN_FLAG;
						call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
						call Sender.send(myMsg, mySocket.dest.addr);

					}
				}
			}
		}
		if(flags == FIN_FLAG || flags == FIN_ACK){
			if(flags == FIN_FLAG){
				mySocket = getSocket(destPort, srcPort);
				mySocket.state = CLOSED;
				mySocket.dest.port = srcPort;
				mySocket.dest.addr = package->src;
				myTCPPack = (tcp_pack *)(myMsg.payload);
				myTCPPack->destPort = mySocket.dest.port;
				myTCPPack->srcPort = mySocket.src.port;
				myTCPPack->seq = 1;
				myTCPPack->ACK = seq + 1;
				myTCPPack->flags = FIN_ACK;
				
				call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(myMsg, mySocket.dest.addr);
			}
			if(flags == FIN_ACK){
				mySocket = getSocket(destPort, srcPort);
				mySocket.state = CLOSED;
			}
		}
}

	command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
		uint16_t temp = 0;
		uint16_t j = 0;
		socket_t mySocket = fd;
		uint16_t readLength = 0;
		uint32_t key;
		bool isWrap;
			
		//mySocket = getSocket(mySocket.dest.port, mySocket.src.port);
		key = call Transport.getKey(fd.src.port, fd.dest.port, fd.dest.addr);
		
		if(call socketHasth.contains(key)){
			mySocket = call socketHash.get(key);
		}else{
			return;
		}
		
		if(mySocket.lastRcvd == mySocket.lastRead){
			return 0;
		} else if (mySocket.lastRcvd > mySocket.lastRead){
			isWrap = FALSE;
			readLength = mySocket.lastRcvd - mySocket.lastRead;
		} else {
			isWrap = TRUE;
			readLength = (SOCKET_BUFFER_SIZE - mySocket.lastRead) + mySocket.lastRcvd;
		}
		
		if(bufflen < readLength){
			readLength = bufflen;
		}

		if(isWrap == TRUE){
			memcpy(buff, mySocket.rcvdBuff + mySocket.lastRead, (SOCKET_BUFFER_SIZE - mySocket.lastRead)*sizeof(uint8_t));
			memcpy(buff + (SOCKET_BUFFER_SIZE - mySocket.lastRead), mySocket.rcvdBuff, (readLength - SOCKET_BUFFER_SIZE - mySocket.lastRead)*sizeof(uint8_t));

			if(readLength < (SOCKET_BUFFER_SIZE - mySocket.lastRead)){
				mySocket.lastRead += readLength;
			} else {
				mySocket.lastRead = (readLength - SOCKET_BUFFER_SIZE - mySocket.lastRead);
			}
		}else{
			memcpy(buff, mySocket.rcvdBuff + mySocket.lastRead, (readLength)*sizeof(uint8_t));
			mySocket.lastRead += readLength;
		}
		
		if(mySocket.lastRead > SOCKET_BUFFER_SIZE){
			mySocket.lastRead -= SOCKET_BUFFER_SIZE;
		}
		return readLength;

}
	command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
		pack myMsg;
		tcp_pack* myTCPPack;
		socket_t mySocket;

	
		myTCPPack = (tcp_pack*)(myMsg.payload);
		myTCPPack->flags = SYN_FLAG;
		myTCPPack->destPort = fd.dest.port;
		myTCPPack->srcPort = fd.src.port;
		myTCPPack->ACK = 0;
		myTCPPack->seq = 1;
		myTCPPack->window = SOCKET_BUFFER_SIZE;

		call Transport.makePack(&myMsg, TOS_NODE_ID, mySocket.dest.addr, 15, 4, 0, myTCPPack, PACKET_MAX_PAYLOAD_SIZE);

		call Sender.send(myMsg, mySocket.dest.addr);
		mySocket.state = SYN_SENT;
		dbg(ROUTING_CHANNEL, "SYN Sent to %u\n", fd.dest.addr);


		mySocket = call Transport.socket();
		mySocket.state = SYN_SENT;
		
		mySocket.dest.addr = fd.dest.addr;
		mySocket.dest.port = fd.dest.port;
		mySocket.src.addr = TOS_NODE_ID;
		mySocket.src.port = fd.src.port;

		key = call Transport.getKey(fd.src.port, fd.dest.port, fd.dest.addr);
		call socketHash.insert(key, mySocket);

}
	command error_t Transport.close(socket_t fd){

		//never used
		socket_t mySocket = fd;
		mySocket.state = CLOSED;
		
}
	command error_t Transport.release(socket_t fd){
}
	command error_t Transport.listen(socket_t fd){
		//never used
		socket_t mySocket = fd;
		mySocket.state = LISTEN;
}
	command void Transport.makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
}
}
