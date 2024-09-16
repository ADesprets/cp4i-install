package com.ibm.ad.demo.soap;
import jakarta.xml.ws.Endpoint;

public class CalculatorPublisher {
	public static void main(String[] args) {
	   // Endpoint.create(new CalculatorWebServiceImpl());
	   Endpoint.publish("/add", new CalculatorWebServiceImpl());
    }
}
