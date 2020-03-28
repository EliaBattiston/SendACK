/**
 *  Source file for implementation of module sendAckC in which
 *  the node 1 send a request to node 2 until it receives a response.
 *  The reply message contains a reading from the Fake Sensor.
 *
 *  @author Luca Pietro Borsani
 */

#include "Timer.h"
#include "sendAck.h"

module sendAckC
{

	uses
	{
		/****** INTERFACES *****/
		interface Boot;

		interface Receive;
		interface AMSend;
		interface SplitControl;
		interface Packet;
		interface PacketAcknowledgements;
		interface Timer<TMilli> as MilliTimer;

		//interface used to perform sensor reading (to get the value from a sensor)
		interface Read<uint16_t>;
	}
}
implementation
{

	uint16_t counter = 0;
	message_t packet;

	bool transmitting = FALSE;

	void sendReq();
	void sendResp();

	//***************** Send request function ********************//
	void sendReq()
	{
		/* This function is called when we want to send a request
	 *
	 * STEPS:
	 * 1. Prepare the msg
	 * 2. Set the ACK flag for the message using the PacketAcknowledgements interface
	 *     (read the docs)
	 * 3. Send an UNICAST message to the correct node
	 * X. Use debug statements showing what's happening (i.e. message fields)
	 */

		if(transmitting)
		{
			return;
		}
		else
		{
			//Create packet
			my_msg_t* message = (my_msg_t*)call Packet.getPayload(&packet, sizeof(my_msg_t));
			if(message == NULL)
			{
				dbg("radio", "ERR: Unable to create request packet\n");
				return;
			}


			message->msg_type = REQ;
			message->msg_counter = counter;
			message->value = 0; //Set to 0 since there is nothing to send from the first mote

			//Set the ACK flag
			call PacketAcknowledgements.requestAck(&packet);
			
			//Send the message to mote 2
			if( call AMSend.send(2, &packet, sizeof(my_msg_t)) == SUCCESS )
			{
				dbg("radio", "Sending request %hu \n", counter);
				//Lock transmission until it ends
				transmitting = TRUE;
			}
		}
	}

	//****************** Task send response *****************//
	void sendResp()
	{
		/* This function is called when we receive the REQ message.
  	 * Nothing to do here. 
  	 * `call Read.read()` reads from the fake sensor.
  	 * When the reading is done it raise the event read one.
  	 */
		call Read.read();
	}

	//***************** Boot interface ********************//
	event void Boot.booted()
	{
		dbg("boot", "Application booted\n");
		
		if(TOS_NODE_ID == 1) //The requester starts the timer
		{
			call MilliTimer.startPeriodic(1000);
		}

		//Start the radio
		call SplitControl.start();
	}

	//***************** SplitControl interface ********************//
	event void SplitControl.startDone(error_t err)
	{
		if(err == SUCCESS)
		{
			dbg("radio", "Radio started\n");
		}
		else
		{
			dbg("radio", "ERR: Radio failed to start, trying again...\n");
			call SplitControl.start();
		}
	}

	event void SplitControl.stopDone(error_t err)
	{
		//Debug statements even if this event will never fire, just in case
		if(err == SUCCESS)
		{
			dbg("radio", "Radio stopped\n");
		}
		else
		{
			dbg("radio", "ERR: Radio failed to stop\n");
		}
	}

	//***************** MilliTimer interface ********************//
	event void MilliTimer.fired()
	{
		/* This event is triggered every time the timer fires.
	 * When the timer fires, we send a request
	 * Fill this part...
	 */
		sendReq();
	}

	//********************* AMSend interface ****************//
	event void AMSend.sendDone(message_t* buf, error_t err)
	{
		/* This event is triggered when a message is sent 
	 *
	 * STEPS:
	 * 1. Check if the packet is sent
	 * 2. Check if the ACK is received (read the docs)
	 * 2a. If yes, stop the timer. The program is done
	 * 2b. Otherwise, send again the request
	 * X. Use debug statements showing what's happening (i.e. message fields)
	 */
		if(&packet == buf)
		{
			//Remove transmission lock when our packet finished being sent
			transmitting = FALSE;

			if(TOS_NODE_ID == 1) //Increment the counter if on mote 1
			{
				counter++;
			}

			if(call PacketAcknowledgements.wasAcked(buf))
			{
				switch(TOS_NODE_ID)
				{
					case 1:
					{
						dbg("radio_ack", "REQ correctly sent and acknowledged\n");
						//Don't send other packages
						call MilliTimer.stop();
						break;
					}
					case 2:
					{
						dbg("radio_ack", "RESP correctly sent and acknowledged\n");
						break;
					}
				}
			}
			else
			{
				dbg("radio_ack", "ERR: The packet was not acknowledged\n");
			}
		}
	}

	//***************************** Receive interface *****************//
	event message_t *Receive.receive(message_t* buf, void *payload, uint8_t len)
	{
		/* This event is triggered when a message is received 
	 *
	 * STEPS:
	 * 1. Read the content of the message
	 * 2. Check if the type is request (REQ)
	 * 3. If a request is received, send the response
	 * X. Use debug statements showing what's happening (i.e. message fields)
	 */
		if(len != sizeof(my_msg_t))
		{
			dbg("radio_rec", "ERR: Received a packet of wrong size\n");
		}
		else
		{
			my_msg_t* message = (my_msg_t*)payload;

			switch(message->msg_type)
			{
				case RESP: //Received by mote 1
				{
					dbg("radio_rec", "Received response with counter %hu and value %hu \n", message->msg_counter, message->value);
					break;
				}
				case REQ: //Received by mote 2
				{
					counter = message->msg_counter;
					sendResp();
					break;
				}
			}
		}

		return buf;
	}

	//************************* Read interface **********************//
	event void Read.readDone(error_t result, uint16_t data)
	{
		/* This event is triggered when the fake sensor finish to read (after a Read.read()) 
	 *
	 * STEPS:
	 * 1. Prepare the response (RESP)
	 * 2. Send back (with a unicast message) the response
	 * X. Use debug statement showing what's happening (i.e. message fields)
	 */
		if(result == SUCCESS)
		{
			if(transmitting)
			{
				return;
			}
			else
			{
				//Create packet
				my_msg_t* message = (my_msg_t*)call Packet.getPayload(&packet, sizeof(my_msg_t));
				if(message == NULL)
				{
					dbg("radio", "ERR: Unable to create request packet\n");
					return;
				}


				message->msg_type = RESP;
				message->msg_counter = counter;
				message->value = data; //Set to 0 since there is nothing to send from the first mote

				//Set the ACK flag
				call PacketAcknowledgements.requestAck(&packet); 
				
				//Send the message to mote 1
				if( call AMSend.send(1, &packet, sizeof(my_msg_t)) == SUCCESS )
				{
					dbg("radio", "Sending response %hu with value %hu \n", counter, data);
					//Lock transmission until it ends
					transmitting = TRUE;
				}
			}
		}
		else
		{
			dbg("sensor", "ERR: Unable to get a value from the sensor\n");
		}
		
	}
}