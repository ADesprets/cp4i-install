
package com.ibm.ad.demo.soap.jaxws;

import jakarta.xml.bind.annotation.XmlAccessType;
import jakarta.xml.bind.annotation.XmlAccessorType;
import jakarta.xml.bind.annotation.XmlRootElement;
import jakarta.xml.bind.annotation.XmlType;


/**
 * This class was generated by the JAX-WS RI.
 * JAX-WS RI 3.0.2
 * Generated source version: 3.0.2
 * 
 */
@XmlRootElement(name = "AddNumbersException", namespace = "http://com.ibm.ad.demo.soap")
@XmlAccessorType(XmlAccessType.FIELD)
@XmlType(name = "AddNumbersException", namespace = "http://com.ibm.ad.demo.soap", propOrder = {
    "detail",
    "message"
})
public class AddNumbersExceptionBean {

    private String detail;
    private String message;

    /**
     * 
     * @return
     *     returns String
     */
    public String getDetail() {
        return this.detail;
    }

    /**
     * 
     * @param detail
     *     the value for the detail property
     */
    public void setDetail(String detail) {
        this.detail = detail;
    }

    /**
     * 
     * @return
     *     returns String
     */
    public String getMessage() {
        return this.message;
    }

    /**
     * 
     * @param message
     *     the value for the message property
     */
    public void setMessage(String message) {
        this.message = message;
    }

}
