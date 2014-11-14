        //popover need to be initialized
        var table_heavy = null;
        var table_light = null;


        $('a[data-toggle=popover]').popover();

        function load_heavy_table(){
           table_heavy = $('#table_heavy').dataTable( {
                  dom: 'T<"clear">lfrtip',
                  tableTools: {
                      "sRowSelect": "os",
                      "aButtons": [ "select_all", "select_none" ]
                  },
                  "lengthMenu": [[10, 25, 50, 100], [10, 25, 50,100]],
                  "scrollY":        "350px",
                  "scrollCollapse": true,
                  "sAjaxDataProp": "data",
                  "processing": true,
                  "serverSide": true,
                  "ajax": "/api/get_heavy_sequence",
                  "columns": [
                      { "data": "sequence_id" },
                      { "data": "sequence_name" },
                      { "data": "putative_annotation_best_v" },
                      { "data": "putative_annotation_best_d" },
                      { "data": "putative_annotation_best_j" },
                  ]
                });
        }

        function load_light_table() {
            table_light = $('#table_light').dataTable( {
                  dom: 'T<"clear">lfrtip',
                  tableTools: {
                      "sRowSelect": "multi",
                      "aButtons": [ "select_all", "select_none" ]
                  },
                  "lengthMenu": [[10, 25, 50, 100], [10, 25, 50,100]],
                  "scrollY":        "350px",
                  "scrollCollapse": true,
                  "sAjaxDataProp": "data",
                  "processing": true,
                  "serverSide": true,
                  "ajax": "/api/get_light_sequence",
                  "columns": [
                      { "data": "sequence_id" },
                      { "data": "sequence_name" },
                      { "data": "putative_annotation_best_v" },
                      { "data": "putative_annotation_best_j" },
 
                  ]
                });
        }

        $(document).ready(function(){
                                     load_heavy_table();
                                    load_light_table();
                  
                 $('.inner').cascadingDropdown({
                    selectBoxes: [
                    {
                      selector: '.study',
					  paramName: 'study_id',
                    },
                    {
                      selector: '.assay',
                      requires: ['.study'],
 					  paramName: 'assay_id',
             		  source: '/api/assaylist',
	 	 			  textKey: 'label',
				 	  valueKey: 'value',
                    },
                    {
                        selector: '.clustering',
                        requires: ['.study', '.assay'],
						requireAll: true,
                    },
                    {
                        selector: '.analysis_heavy',
                        requires: ['.study', '.assay', '.clustering'],
						requireAll: true,
						source: '/api/igblastlist',
     	 			    textKey: 'label',
				 	    valueKey: 'value',
                      },
                     {
                        selector: '.analysis_light',
                        requires: ['.study', '.assay', '.clustering' ],
						requireAll: true,
						source: '/api/igblastlist',
     	 			    textKey: 'label',
				 	    valueKey: 'value',
                      }
                    ]
                  });
            
                 $("#cluster").change(function () {
                                 if ($(this).val() == 0){
                                    $('#table_heavy').dataTable().fnDestroy();
                                    $('#table_light').dataTable().fnDestroy();
                                    $('#heavy_chain_panel_body').removeClass('in');
                                    $('#light_chain_panel_body').removeClass('in');

                                 }
                                 else if ($(this).val() == 1){
                                    $('#table_heavy').dataTable().fnDestroy();
                                    $('#table_light').dataTable().fnDestroy();
                                    $('#heavy_chain_panel_body').collapse('show');
                                    $('#light_chain_panel_body').removeClass('in');
                                    load_heavy_table();
                                 }
                                 else if ($(this).val() == 2){
                                    $('#table_heavy').dataTable().fnDestroy();
                                    $('#table_light').dataTable().fnDestroy();
                                    $('#heavy_chain_panel_body').removeClass('in');
                                    $('#light_chain_panel_body').collapse('show');
                                    load_light_table();
                                 }
                                 else if ($(this).val() == 3){
                                    $('#table_heavy').dataTable().fnDestroy();
                                    $('#table_light').dataTable().fnDestroy();
                                    $('#heavy_chain_panel_body').collapse('show');
                                    $('#light_chain_panel_body').collapse('show');
                                    load_heavy_table();
                                    load_light_table();
 
                                 }
                   });
	        });


