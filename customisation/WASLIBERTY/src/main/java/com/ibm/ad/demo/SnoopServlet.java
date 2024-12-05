package com.ibm.ad.demo;

import java.io.IOException;
import java.io.PrintWriter;
import java.security.cert.X509Certificate;
import java.util.Date;
import java.util.Enumeration;
import java.util.Locale;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(description = "THE Snoop servlet", urlPatterns = { "/SnoopServlet", "/snoop" })
public class SnoopServlet extends HttpServlet {
	private static final long serialVersionUID = 1L;

	public static long getSerialversionuid() {
		return serialVersionUID;
	}

	/**
	 * @see HttpServlet#doGet(HttpServletRequest request, HttpServletResponse
	 *      response)
	 */
	protected void doGet(HttpServletRequest request, HttpServletResponse response)
			throws ServletException, IOException {

		PrintWriter out;

		response.setContentType("text/html");
		out = response.getWriter();

		out.println("<HTML><HEAD><TITLE>Snoop Servlet</TITLE></HEAD><BODY BGCOLOR=\"#FFFFEE\">");
		out.println("<h1>Snoop Servlet - Request/Client Information</h1>");
		out.println("<h2>Requested URL:</h2>");
		out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
		out.println("<tr><td>" + escapeChar(request.getRequestURI()) + "</td></tr></table><BR><BR>");

		out.println("<h2>Servlet Name:</h2>");
		out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
		out.println("<tr><td>" + escapeChar(getServletConfig().getServletName()) + "</td></tr></table><BR><BR>");

		Enumeration<String> vEnum = getServletConfig().getInitParameterNames();
		if (vEnum != null && vEnum.hasMoreElements()) {
			boolean first = true;
			while (vEnum.hasMoreElements()) {
				if (first) {
					out.println("<h2>Servlet Initialization Parameters</h2>");
					out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
					first = false;
				}
				String param = (String) vEnum.nextElement();
				out.println("<tr><td>" + escapeChar(param) + "</td><td>" + escapeChar(getInitParameter(param))
						+ "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		vEnum = getServletConfig().getServletContext().getInitParameterNames();
		if (vEnum != null && vEnum.hasMoreElements()) {
			boolean first = true;
			while (vEnum.hasMoreElements()) {
				if (first) {
					out.println("<h2>Servlet Context Initialization Parameters</h2>");
					out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
					first = false;
				}
				String param = (String) vEnum.nextElement();
				out.println("<tr><td>" + escapeChar(param) + "</td><td>"
						+ escapeChar(getServletConfig().getServletContext().getInitParameter(param)) + "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		out.println("<h2>Request Information:</h2>");
		out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
		print(out, "Request method", request.getMethod());
		print(out, "Request URI", request.getRequestURI());
		print(out, "Request protocol", request.getProtocol());
		print(out, "Servlet path", request.getServletPath());
		print(out, "Path info", request.getPathInfo());
		print(out, "Path translated", request.getPathTranslated());
		print(out, "Character encoding", request.getCharacterEncoding());
		print(out, "Query string", request.getQueryString());
		print(out, "Content length", request.getContentLength());
		print(out, "Content type", request.getContentType());
		print(out, "Server name", request.getServerName());
		print(out, "Server port", request.getServerPort());
		print(out, "Remote user", request.getRemoteUser());
		print(out, "Remote address", request.getRemoteAddr());
		print(out, "Remote host", request.getRemoteHost());
		print(out, "Remote port", request.getRemotePort());
		print(out, "Local address", request.getLocalAddr());
		print(out, "Local host", request.getLocalName());
		print(out, "Local port", request.getLocalPort());
		print(out, "Authorization scheme", request.getAuthType());
		if (request.getLocale() != null) {
			print(out, "Preferred Client Locale", request.getLocale().toString());
		} else {
			print(out, "Preferred Client Locale", "none");
		}
		Enumeration<Locale> ee = request.getLocales();
		while (ee.hasMoreElements()) {
			Locale cLocale = (Locale) ee.nextElement();
			if (cLocale != null) {
				print(out, "All Client Locales", cLocale.toString());
			} else {
				print(out, "All Client Locales", "none");
			}
		}
		print(out, "Context Path", escapeChar(request.getContextPath()));
		if (request.getUserPrincipal() != null) {
			print(out, "User Principal", escapeChar(request.getUserPrincipal().getName()));
		} else {
			print(out, "User Principal", "none");
		}
		out.println("</table><BR><BR>");

		Enumeration<String> e = request.getHeaderNames();
		if (e.hasMoreElements()) {
			out.println("<h2>Request headers:</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			while (e.hasMoreElements()) {
				String name = (String) e.nextElement();
				out.println("<tr><td>" + escapeChar(name) + "</td><td>" + escapeChar(request.getHeader(name))
						+ "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		e = request.getParameterNames();
		if (e.hasMoreElements()) {
			out.println("<h2>Servlet parameters (Single Value style):</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			while (e.hasMoreElements()) {
				String name = (String) e.nextElement();
				out.println("<tr><td>" + escapeChar(name) + "</td><td>" + escapeChar(request.getParameter(name))
						+ "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		e = request.getParameterNames();
		if (e.hasMoreElements()) {
			out.println("<h2>Servlet parameters (Multiple Value style):</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			while (e.hasMoreElements()) {
				String name = (String) e.nextElement();
				String vals[] = (String[]) request.getParameterValues(name);
				if (vals != null) {

					out.print("<tr><td>" + escapeChar(name) + "</td><td>");
					out.print(escapeChar(vals[0]));
					for (int i = 1; i < vals.length; i++)
						out.print(", " + escapeChar(vals[i]));
					out.println("</td></tr>");
				}
			}
			out.println("</table><BR><BR>");
		}

		String cipherSuite = (String) request.getAttribute("javax.net.ssl.cipher_suite");
		if (cipherSuite != null) {
			X509Certificate certChain[] = (X509Certificate[]) request.getAttribute("javax.net.ssl.peer_certificates");

			out.println("<h2>HTTPS Information:</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			out.println("<tr><td>Cipher Suite</td><td>" + escapeChar(cipherSuite) + "</td></tr>");

			if (certChain != null) {
				for (int i = 0; i < certChain.length; i++) {
					out.println("client cert chain [" + i + "] = " + escapeChar(certChain[i].toString()));
				}
			}
			out.println("</table><BR><BR>");
		}

		Cookie[] cookies = request.getCookies();
		if (cookies != null && cookies.length > 0) {
			out.println("<H2>Client cookies</H2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			for (int i = 0; i < cookies.length; i++) {
				out.println("<tr><td>" + escapeChar(cookies[i].getName()) + "</td><td>"
						+ escapeChar(cookies[i].getValue()) + "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		e = request.getAttributeNames();
		if (e.hasMoreElements()) {
			out.println("<h2>Request attributes:</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			while (e.hasMoreElements()) {
				String name = (String) e.nextElement();
				out.println("<tr><td>" + escapeChar(name) + "</td><td>"
						+ escapeChar(request.getAttribute(name).toString()) + "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		e = getServletContext().getAttributeNames();
		if (e.hasMoreElements()) {
			out.println("<h2>ServletContext attributes:</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			while (e.hasMoreElements()) {
				String name = (String) e.nextElement();
				out.println("<tr><td>" + escapeChar(name) + "</td><td>"
						+ escapeChar(getServletContext().getAttribute(name).toString()) + "</td></tr>");
			}
			out.println("</table><BR><BR>");
		}

		HttpSession session = request.getSession(false);
		if (session != null) {
			out.println("<h2>Session information:</h2>");
			out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");
			print(out, "Session ID", session.getId());
			print(out, "Last accessed time", new Date(session.getLastAccessedTime()).toString());
			print(out, "Creation time", new Date(session.getCreationTime()).toString());
			String mechanism = "unknown";
			if (request.isRequestedSessionIdFromCookie()) {
				mechanism = "cookie";
			} else if (request.isRequestedSessionIdFromURL()) {
				mechanism = "url-encoding";
			}
			print(out, "Session-tracking mechanism", mechanism);
			out.println("</table><BR><BR>");

			Enumeration<String> vals = session.getAttributeNames();
			if (vals.hasMoreElements()) {
				out.println("<h2>Session values</h2>");
				out.println("<TABLE Border=\"2\" WIDTH=\"65%\" BGCOLOR=\"#DDDDFF\">");

				while (vals.hasMoreElements()) {
					String name = (String) vals.nextElement();
					out.println("<tr><td>" + escapeChar(name) + "</td><td>"
							+ escapeChar(session.getAttribute(name).toString()) + "</td></tr>");
				}
				out.println("</table><BR><BR>");
			}
		}

		out.println("</body></html>");
	}

	/**
	 * @see HttpServlet#doPost(HttpServletRequest request, HttpServletResponse
	 *      response)
	 */
	protected void doPost(HttpServletRequest request, HttpServletResponse response)
			throws ServletException, IOException {
		doGet(request, response);
	}

	private void print(PrintWriter out, String name, String value) {
		out.println(
				"<tr><td>" + name + "</td><td>" + (value == null ? "&lt;none&gt;" : escapeChar(value)) + "</td></tr>");
	}

	private void print(PrintWriter out, String name, int value) {
		out.print("<tr><td>" + name + "</td><td>");
		if (value == -1) {
			out.print("&lt;none&gt;");
		} else {
			out.print(value);
		}
		out.println("</td></tr>");
	}

	private String escapeChar(String str) {
		char src[] = str.toCharArray();
		int len = src.length;
		for (int i = 0; i < src.length; i++) {
			switch (src[i]) {
			case '<': // to "&lt;"
				len += 3;
				break;
			case '>': // to "&gt;"
				len += 3;
				break;
			case '&': // to "&amp;"
				len += 4;
				break;
			}
		}
		char ret[] = new char[len];
		int j = 0;
		for (int i = 0; i < src.length; i++) {
			switch (src[i]) {
			case '<': // to "&lt;"
				ret[j++] = '&';
				ret[j++] = 'l';
				ret[j++] = 't';
				ret[j++] = ';';
				break;
			case '>': // to "&gt;"
				ret[j++] = '&';
				ret[j++] = 'g';
				ret[j++] = 't';
				ret[j++] = ';';
				break;
			case '&': // to "&amp;"
				ret[j++] = '&';
				ret[j++] = 'a';
				ret[j++] = 'm';
				ret[j++] = 'p';
				ret[j++] = ';';
				break;
			default:
				ret[j++] = src[i];
				break;
			}
		}
		return new String(ret);
	}

}
