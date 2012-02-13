
// ConfigurationManagementFactory.java --
//
// ConfigurationManagementFactory.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.esx.client;

import ecinternal.client.InternalComponentBaseFactory;
import ecinternal.client.InternalFormBase;
import ecinternal.client.PropertySheetEditor;

import com.electriccloud.commander.gwt.client.BrowserContext;
import com.electriccloud.commander.gwt.client.Component;
import com.electriccloud.commander.gwt.client.ComponentContext;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createPageUrl;

public class ConfigurationManagementFactory
    extends InternalComponentBaseFactory
{

    //~ Methods ----------------------------------------------------------------

    @Override public Component createComponent(ComponentContext jso)
    {
        String    panel     = jso.getParameter("panel");
        Component component;

        if ("create".equals(panel)) {
            component = new CreateConfiguration();
        }
        else if ("edit".equals(panel)) {
            String configName    = BrowserContext.getInstance()
                                                 .getGetParameter("configName");
            String propSheetPath = "/plugins/" + getPluginName()
                    + "/project/esx_cfgs/" + configName;
            String formXmlPath   = "/plugins/" + getPluginName()
                    + "/project/ui_forms/ESXEditConfigForm";

            component = new PropertySheetEditor("ecgc",
                    "Edit ESX Configuration", configName, propSheetPath,
                    formXmlPath, getPluginName());

            ((InternalFormBase) component).setDefaultRedirectToUrl(
                createPageUrl(getPluginName(), "configurations").buildString());
        }
        else {

            // Default panel is "list"
            component = new ConfigurationList();
        }

        return component;
    }
}