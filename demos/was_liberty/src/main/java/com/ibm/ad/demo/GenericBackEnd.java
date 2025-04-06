package com.ibm.ad.demo;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Enumeration;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Servlet implementation class GenericBackEnd
 * Sample call: curl -u "admin:admin" -H "accept: application/json" -H "content-type: application/json" -d "{\"b1\":\"v1\"}" http://localhost:9080/demo/be
 */
@WebServlet(name = "GenericBackendServlet", description = "Servlet that returns information from the sender", urlPatterns = "/be")
public class GenericBackEnd extends HttpServlet {
    private static final long serialVersionUID = 1L;

    /**
     * @see HttpServlet#doGet(HttpServletRequest request, HttpServletResponse
     *      response)
     */
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.getWriter().append(getJSONResponse(request));
    }

    /**
     * @see HttpServlet#doPost(HttpServletRequest request, HttpServletResponse
     *      response)
     */
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.getWriter().append(getJSONResponse(request));
    }

    @Override
    protected void doDelete(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        resp.setContentType("application/json");
        resp.getWriter().append(getJSONResponse(req));
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        resp.setContentType("application/json");
        resp.getWriter().append(getJSONResponse(req));
    }

    protected void doPatch(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        resp.setContentType("application/json");
        resp.getWriter().append(getJSONResponse(req));
    }

    @Override
    protected void doOptions(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        resp.setContentType("application/json");
        resp.getWriter().append(getJSONResponse(req));
    }

    @Override
    protected void doHead(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        resp.setContentType("application/json");
        resp.getWriter().append(getJSONResponse(req));
    }

    public String getJSONResponse(HttpServletRequest request) {
        SimpleDateFormat formatter = new SimpleDateFormat("yyyy-MM-dd 'at' HH:mm:ss z");
        Date now = new Date(System.currentTimeMillis());

        StringBuffer sb = new StringBuffer();
        sb.append("{\"date\" : \"");
        sb.append(formatter.format(now));
        sb.append("\",\"Request Method\" : \"");
        sb.append(request.getMethod());
        sb.append("\",\"Request URI\" : \"");
        sb.append(request.getRequestURI());
        sb.append("\",\"Request Protocol\" : \"");
        sb.append(request.getProtocol());
        sb.append("\",\"Servlet Path\" : \"");
        sb.append(request.getServletPath());
        sb.append("\",\"Path Info\" : \"");
        sb.append(request.getPathInfo());
        sb.append("\",\"Path Translated\" : \"");
        sb.append(request.getPathTranslated());
        sb.append("\",\"Query String\" : \"");
        sb.append(request.getQueryString());
        sb.append("\",\"Content Length\" : \"");
        sb.append(request.getContentLength());
        sb.append("\",\"Content Type\" : \"");
        sb.append(request.getContentType());
        sb.append("\",\"Server Name\" : \"");
        sb.append(request.getServerName());
        sb.append("\",\"Server Port\" : \"");
        sb.append(request.getServerPort());
        sb.append("\",\"Remote User\" : \"");
        sb.append(request.getRemoteUser());
        sb.append("\",\"Remote Address\" : \"");
        sb.append(request.getRemoteAddr());
        sb.append("\",\"Remote Host\" : \"");
        sb.append(request.getRemoteHost());
        sb.append("\",\"Authorization Scheme\" : \"");
        sb.append(request.getAuthType());

        Enumeration<String> e = request.getHeaderNames();
        sb.append("\",\"headers\" : [{\"");
        while (e.hasMoreElements()) {
            String name = (String) e.nextElement();
            sb.append(name);
            sb.append("\" : \"");
            sb.append(request.getHeader(name));
            if (e.hasMoreElements()) {
                sb.append("\"}, {\"");
            } else {
                sb.append("\"}]");
            }
        }

        try {
            if (request.getContentLength() > 0) {
                System.out.println("Content length is : "+ request.getContentLength());

                StringBuilder stringBuilder = new StringBuilder();
                BufferedReader bufferedReader = null;

                try {
                    InputStream inputStream = request.getInputStream();

                    if (inputStream != null) {
                        bufferedReader = new BufferedReader(new InputStreamReader(inputStream, "UTF-8"));

                        char[] charBuffer = new char[128];
                        int bytesRead = -1;

                        while ((bytesRead = bufferedReader.read(charBuffer)) > 0) {
                            stringBuilder.append(charBuffer, 0, bytesRead);
                        }
                    }
                } catch (IOException ex) {
                    throw new IOException();
                } finally {
                    if (bufferedReader != null) {
                        bufferedReader.close();
                    }
                }
                String body = stringBuilder.toString();
                sb.append(", \"body\" :");
                sb.append(body);
            }
        } catch (IOException e1) {
            e1.printStackTrace();
        }

        sb.append("}");
        return sb.toString();
    }
}