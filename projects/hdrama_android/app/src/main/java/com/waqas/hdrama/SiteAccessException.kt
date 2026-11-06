package com.waqas.hdrama

import java.io.IOException

/** Access must be granted by the website, never manufactured by the application. */
class SiteAccessException(
    val pageUrl: String,
    val statusCode: Int? = null,
    val challenged: Boolean = false
) : IOException(
    if (challenged) "The website requires an access check. Tap Check website access."
    else "The website denied app access${statusCode?.let { " (HTTP $it)" }.orEmpty()}. Tap Check website access."
)
