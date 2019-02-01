/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

typedef nx_struct neighbor{
	nx_uint16_t age;
	nx_uint16_t node;
}neighbor;
//move this to the first one
typedef nx_struct sendneighbor{
	nx_uint16_t sendnode;
	nlist neighborList;
}sendneighbor;

typedef nx_struct nlist{
	nx_uint16_t nodeId;
	nx_uint16_t cost;
}nlist;

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

	uses interface Timer<TMilli> as PeriodicTimer;
	uses interface List<pack> as PacketList;
	uses interface List<neighbor *> as NeighborList;
}

implementation{
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	bool findPack(pack *Package);
	void pushPack(pack Package);
	void NeighborDiscovery();
	void printNeighborList();

   event void Boot.booted(){
      call AMControl.start();
	//call neighbordiscovery on a timer
      dbg(GENERAL_CHANNEL, "Booted\n");
	
	call PeriodicTimer.startPeriodicAt(1,500);
	dbg(NEIGHBOR_CHANNEL, "Timer Started");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

	event void PeriodicTimer.fired(){
		NeighborDiscovery();
	}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
		
		if(myMsg->TTL == 0){
			dbg(FLOODING_CHANNEL, "Packet from %d has timed out\n", myMsg->src);
		
		}else if(findPack(myMsg) == TRUE){
			dbg(FLOODING_CHANNEL, "Already got Packet from %d\n", myMsg->src);
		
		}else if(myMsg->dest == TOS_NODE_ID){
			
			if(myMsg->protocol == 0){
				dbg(NEIGHBOR_CHANNEL, "Got Ping from %d\n", myMsg->src);
			
			}else if(myMsg->protocol == 1){
				dbg(NEIGHBOR_CHANNEL, "Got Ping Reply from %d\n", myMsg->src);
			
			}else if(myMsg->protocol == 7){
				dbg(NEIGHBOR_CHANNEL, "Got comand to Print Neighbor List \n");
				printNeighborList();
			
			}else{
				pushPack(*myMsg);
			}
		
		}else if(myMsg->protocol == 0 || myMsg->protocol == 1){

			neighbor* Neighbor, *neighborNodes;
			uint16_t i = 0;
			uint16_t size = call NeighborList.size();
			
			if(myMsg->protocol == 0){
				dbg(NEIGHBOR_CHANNEL, "Got Ping from %d, sending PingReply \n", myMsg->src);
				makePack(&sendPackage, myMsg->src, myMsg->dest, 1, 1, 0, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(sendPackage, myMsg->src);
			
			}else if(myMsg->protocol == 1){
				dbg(NEIGHBOR_CHANNEL, "Got PingReply from %d, adding to Neighbor List \n", myMsg->src);

				//uint16_t i = 0;
				//uint16_t size = call NeighborList.size();
				
				for(i = 0; i <= size; i++){
					neighborNodes = call NeighborList.get(i);
					if(myMsg->src == neighborNodes->node){
						dbg(NEIGHBOR_CHANNEL, "Node %d is already in the Node list\n", myMsg->src);
					}
				}
				dbg(NEIGHBOR_CHANNEL, "Adding Node %d to Node %d neighbor list\n", myMsg->src, TOS_NODE_ID);
				Neighbor->node = myMsg->src;
				Neighbor->age = 0;
				call NeighborList.pushback(Neighbor);
				
			}
			/*else if(myMsg->protocol == 7){
				dbg(NEIGHBOR_CHANNEL, "Got CommandMsg from %d, dumping Neighbor List \n", myMsg->src);
				printNeighborList();
			}*/
		
		}else{
			dbg(FLOODING_CHANNEL, "Packet does not belong to us, trying to send to %d\n", myMsg->dest);
			makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL - 1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
			call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		}
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 20, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destination);
	//sequence number
   }

   event void CommandHandler.printNeighbors(){
	
	uint8_t sizem = call NeighborList.size();
	uint8_t message[5];
	message[0] = 'P';
	message[1] = 'R';
	message[2] = 'I';
	message[3] = 'N';
	message[4] = 'T';

	dbg(GENERAL_CHANNEL, "PRINT NEIGHBOR LIST EVENT \n");
	makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, 2, 7, 0, message, PACKET_MAX_PAYLOAD_SIZE);
	call Sender.send(sendPackage, AM_BROADCAST_ADDR);

	
	makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, 2, 7, 0, (uint8_t**) NeighborList, sizem);
	call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	//fix ttl and print neighors directly
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

  bool findPack(pack *Package){
	uint8_t i = 0;
	uint8_t listSize = call PacketList.size();
	pack matchPack;

	for(i = 0; i <= listSize; i++){
		matchPack = call PacketList.get(i);
		if(Package->src == matchPack.src && Package->payload == matchPack.payload && Package->dest == matchPack.dest){
			return TRUE;
		}
	}
	return FALSE;
   }

   void pushPack(pack Package){
    	call PacketList.pushback(Package);
   }

   void NeighborDiscovery(){

	uint8_t message[4];
	message[0] = 'W';
	message[1] = 'O';
	message[2] = 'R';
	message[3] = 'K';
	
	if(!call NeighborList.isEmpty()){
	
	uint16_t size = call NeighborList.size();
	uint16_t i, j, k = 0;
	neighbor* neighborNodes;
	//neighbor* temp;
	//neighbor* last;
	
		for(i = 0; i <= size; i++){
			neighborNodes = call NeighborList.get(i);
			neighborNodes->age++;
		
			if(neighborNodes->age > 5){
				dbg(NEIGHBOR_CHANNEL, "Neighbor %d is too old", neighborNodes->node);
				neighborNodes = call NeighborList.remove(i);
				size--;
				i--;
				/*temp = call NeighborList.get(i);
				temp->node = 0;
				temp->age = 99;

				for(j = 0; j <= size; j++){
					temp = call NeighborList.get(j);
					k = j;
				
					if(temp->node == 0 && temp->age == 99){
						
						for(k = 0; k <= size - 1; k++){
							temp = call NeighborList.get(k + 1);
							call NeighborList.get(k) = temp;
						}
					
					last = call NeighborList.get(size);
					last->node = NULL;
					last->age = NULL;
					size--;
					}
				}*/
			}
		}
	}
     	makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, 0, 0, message, PACKET_MAX_PAYLOAD_SIZE);
	call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   void printNeighborList(){
	
	uint8_t size = call NeighborList.size();
	uint8_t i = 0;
		
	if(size == 0){
		dbg(NEIGHBOR_CHANNEL, "No Neighbors\n");
	}

	for(i = 0; i <= size; i++){
		neighbor* neighborNodes = call NeighborList.get(i);
		dbg(NEIGHBOR_CHANNEL, "Neighbor: %d Age: %d \n", neighborNodes->node, neighborNodes->age);
	}
   }
}
