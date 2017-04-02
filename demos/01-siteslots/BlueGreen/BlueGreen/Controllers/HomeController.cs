using System;
using System.Collections.Generic;
using System.Configuration;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace BlueGreen.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            ViewBag.WhichEnvironment = ConfigurationManager.AppSettings["WhatIsMyEnvironment"];
            ViewBag.ApplicationName = ConfigurationManager.AppSettings["ApplicationName"];
            ViewBag.Color = ConfigurationManager.AppSettings["Color"];
            ViewBag.Version = ConfigurationManager.AppSettings["Version"];
            ViewBag.DatabaseConnectionString = ConfigurationManager.ConnectionStrings["DatabaseConnectionString"].ConnectionString;
            return View();
        }
    }
}