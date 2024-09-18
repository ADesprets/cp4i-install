package com.ibm.ad.demo.soap;

import jakarta.jws.WebService;
import jakarta.jws.WebMethod;

@WebService  (serviceName="CalculatorWebService", targetNamespace="http://com.ibm.ad.demo.soap", portName="CalculatorWebServicePort") // , name="CalculatorWebService", endpointInterface = "com.ibm.ad.demo.soap.CalculatorWebService"
public class CalculatorWebServiceImpl implements CalculatorWebService {
    @WebMethod
    public int add(int num1, int num2) throws AddNumbersException{
        if (num1 < 0 || num2 < 0) {
            throw new AddNumbersException("Negative numbers cant be added!",
                "Numbers: " + num1 + ", " + num2);
        }
        return num1 + num2;
    }
}
