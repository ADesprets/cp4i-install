package com.ibm.ad.demo.soap;

import jakarta.jws.WebService;
import jakarta.jws.WebMethod;
import jakarta.jws.WebParam;
import jakarta.jws.soap.SOAPBinding;
import jakarta.jws.soap.SOAPBinding.Style;
import jakarta.jws.soap.SOAPBinding.Use;

@WebService (name = "CalculatorWebService", targetNamespace = "http://com.ibm.ad.demo.soap", wsdlLocation="WEB-INF/wsdl/CalculatorWebService.wsdl")
@SOAPBinding(style = Style.DOCUMENT, use = Use.LITERAL) //optional , parameterStyle = ParameterStyle.WRAPPED
public interface CalculatorWebService{
    @WebMethod
    int add(@WebParam(name="num1", partName="num1") int num1, @WebParam(name="num2", partName="num2") int num2) throws AddNumbersException;
}
