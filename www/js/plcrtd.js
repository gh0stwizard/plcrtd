$( function() {
  var suffix = '/plcrtd',
      addr = window.location.protocol + '//' + window.location.host
      ra = addr + suffix + '?',
      errors = [
        'Connection error',
        'Bad request',
        'Not implemented',
        'Internal error'
      ],
      bitsOptions = [ 1024, 2048, 4096 ];


  function AppViewModel() {
    var self = this;

    /*  Data  */

    self.onAJAX = ko.observable();
    self.errorMessage = ko.observable();
    self.errorDescription = ko.observable();

    /*  Data: this app  */

    self.onAbout = ko.observable();
    self.onCA = ko.observable();
    self.onClient = ko.observable();
    self.onPKCS = ko.observable();


    self.onConfigure = ko.observable();
    self.onUpdateDB = ko.observable();
    self.onWipeDBs = ko.observable();

    self.dbname = ko.observable();
    self.dbdesc = ko.observable();
    self.dbopen = ko.observable();
    self.DBList = ko.observableArray( [ ] );
    self.onDBTable = ko.observable( false );
    
    self.isUpdate = ko.observable( false );
    
    self.tUpdateDB = function () {
      self.dbname( null );
      self.dbdesc( null );
    
      self.onWipeDBs( false );
      self.onDBTable( false );
      
      if ( self.onUpdateDB() ) {
        self.onUpdateDB( false );
        self.onDBTable( true );
        self.isUpdate( true );
      } else {
        self.onUpdateDB( true );
        self.onDBTable( false );
        self.isUpdate( false );
      }
      
      return false;
    }
    
    self.tWipeDBs = function () {
      self.onUpdateDB( false );
      self.onDBTable( false );

      if ( self.onWipeDBs() ) {
        self.onWipeDBs( false );
        self.onDBTable( true );
      } else {
        self.onWipeDBs( true );
      }
    }    

    self.inCAPassword = ko.observable();
    self.inCABits = ko.observable();
    self.inCADays = ko.observable();
    self.inCASubject = ko.observable();

    self.outCAkey = ko.observable();
    self.genCAkeyReady = ko.observable();

    self.outCAcrt = ko.observable();
    self.genCAcrtReady = ko.observable();


    self.inClientPassword = ko.observable();
    self.inClientBits = ko.observable();
    self.inClientDays = ko.observable();
    self.inClientSubject = ko.observable();
    self.inClientSerial = ko.observable();
    self.inClientCAPassword = ko.observable();
    self.inClientCAkey = ko.observable();
    self.inClientCAcrt = ko.observable();

    self.outClientKey = ko.observable();
    self.genClientKeyReady = ko.observable();

    self.outClientCsr = ko.observable();
    self.genClientCsrReady = ko.observable();

    self.outClientCrt = ko.observable();
    self.genClientCrtReady = ko.observable();

  
    self.genP12Ready = ko.observable();
    self.inPKCSClientCrt = ko.observable();
    self.inPKCSClientKey = ko.observable();
    self.inPKCSClientPwd = ko.observable();
    self.inPKCSClientXpw = ko.observable();
    
    self.outPKCSpem = ko.observable();
    self.convP12Ready = ko.observable();
    self.inPKCSpemPwd = ko.observable();
    
    self.inPKCSpemFile = ko.observable();


    self.browserCheck = ko.computed( function () {
      var version = parseFloat( navigator.appVersion );

      /* TODO mobile support ? */

      return ( navigator.userAgent.indexOf( "Firefox" ) != -1 
            && version > 20 )
          || ( navigator.userAgent.indexOf( "SeaMonkey" ) != -1 
            && version > 2.0 )
          || ( navigator.userAgent.indexOf( "Chrome" ) != -1
            && version > 14 )
          || ( navigator.userAgent.indexOf( "Firefox" ) != -1
            && version > 15 );
    } );


    /*  Behaviours  */

    self.About  = function () { location.hash = '';       }
    self.CA     = function () { location.hash = 'ca';     }
    self.Client = function () { location.hash = 'client'; }
    self.PKCS   = function () { location.hash = 'pkcs';   }
    
    self.Configure = function () { location.hash = 'configure'; }

    /*  http://caniuse.com/download  */

    self.save = function ( filename, text ) {
      var pom = document.createElement( 'a' );
      pom.setAttribute( 'href',
        'data:text/plain;charset=utf-8,' + encodeURIComponent(text) );
      pom.setAttribute( 'download', filename );

      if ( document.createEvent ) {
        var event = document.createEvent( 'MouseEvents' );
        event.initEvent( 'click', true, true );
        pom.dispatchEvent( event );
      } else {
        pom.click();
      }
    }

    self.genCAkey = function ( cb ) {
      self.outCAkey( null );
      self.outCAcrt( null );
      clearError();
      self.genCAkeyReady( false );

      var pass = self.inCAPassword(),
          bits = self.inCABits();

      postJSON( addr + suffix,
        {
          action: 'genCAkey',
          pass: pass,
          bits: bits
        },
        function ( response ) {
          if ( response.key ) {
            self.outCAkey( response.key );
            $.isFunction( cb ) ? cb() : "";
          } else {
            self.errorMessage( errors[ response.err ] );
            self.errorDescription( response.msg );
          }
          
          self.genCAkeyReady( true );
        }
      );
    }

    self.genCAcrt = function () {
      self.outCAcrt( null );
      clearError();
      self.genCAcrtReady( false );

      var cb = function () {
        var pass = self.inCAPassword(),
            days = self.inCADays(),
            subj = self.inCASubject(),
            key = self.outCAkey();

        postJSON( addr + suffix,
          {
            action: 'genCAcrt',
            pass: pass,
            key: key,
            days: days,
            subj: subj
          },
          function ( response ) {
            if ( response.crt ) {
              self.outCAcrt( response.crt );
            } else {
              self.errorMessage( errors[ response.err ] );
              self.errorDescription( response.msg );
            }
            
            self.genCAcrtReady( true );
          }
        );
      }

      if ( ! self.outCAkey() ) {
        self.genCAkey( cb );
      } else {
        cb();
      }
    }


    self.genClientKey = function ( cb ) {
      self.outClientKey( null );
      self.outClientCsr( null );
      self.outClientCrt( null );
      clearError();
      self.genClientKeyReady( false );

      var pass = self.inClientPassword(),
          bits = self.inClientBits();

      postJSON( addr + suffix,
        { 
          action: 'genClientKey',
          pass: pass,
          bits: bits
        },
        function ( response ) {
          if ( response.key ) {
            self.outClientKey( response.key );
            $.isFunction( cb ) ? cb() : "";
          } else {
            self.errorMessage( errors[ response.err ] );
            self.errorDescription( response.msg );
          }

          self.genClientKeyReady( true );
        }
      );
    }

    self.genClientCsr = function ( cb ) {
      self.outClientCsr( null );
      clearError();
      self.genClientCsrReady( false );

      var mycb = function () {
        var pass = self.inClientPassword(),
            subj = self.inClientSubject(),
            key = self.outClientKey();

        postJSON( addr + suffix,
          {
            action: 'genClientCsr',
            pass: pass,
            key: key,
            subj: subj
          },
          function ( response ) {
            if ( response.csr ) {
              self.outClientCsr( response.csr );
              $.isFunction( cb ) ? cb() : "";
            } else {
              self.errorMessage( errors[ response.err ] );
              self.errorDescription( response.msg );
            }
            
            self.genClientCsrReady( true );
          }
        );
      }

      if ( ! self.outClientKey() ) {
        self.genClientKey( mycb );
      } else {
        mycb();
      }
    }
    
    self.genClientCrt = function () {
      self.outClientCrt( null );
      clearError();
      self.genClientCrtReady( false );

      var mycb = function () {
        var csr = self.outClientCsr(),
            days = self.inClientDays(),
            cacrt = self.inClientCAcrt(),
            cakey = self.inClientCAkey(),
            capass = self.inClientCAPassword(),
            serial = self.inClientSerial();

        postJSON( addr + suffix,
          {
            action: 'genClientCrt',
            serial: serial,
            csr: csr,
            cacrt: cacrt,
            cakey: cakey,
            capass: capass,
            days: days
          },
          function ( response ) {
            if ( response.crt ) {
              self.outClientCrt( response.crt );
            } else {
              self.errorMessage( errors[ response.err ] );
              self.errorDescription( response.msg );
            }
            
            self.genClientCrtReady( true );
          }
        );      
      }
      
      if ( ! self.outClientCsr() ) {
        self.genClientCsr( mycb );
      } else {
        mycb();
      }      
    }


    self.genP12 = function () {
      clearError();
      self.genP12Ready( false );
      
      var key = self.inPKCSClientKey(),
          crt = self.inPKCSClientCrt(),
          pwd = self.inPKCSClientPwd(),
          Xpw = self.inPKCSClientXpw();
      
      
      /*  FIXME  */
      
      $( '<form action=' + addr + suffix + ' method="POST"></form>' )
        .append( '<input type="hidden" name="action" value="genP12" />' )
        .append( '<input type="hidden" name="key" value="' + key + '"/>' )
        .append( '<input type="hidden" name="crt" value="' + crt + '"/>' )
        .append( '<input type="hidden" name="pwd" value="' + pwd + '"/>' )
        .append( '<input type="hidden" name="Xpw" value="' + Xpw + '"/>' )
        .appendTo( 'iframe' );
      
      $( 'iframe' ).find( 'form' ).submit();
      $( 'iframe' ).empty();

      self.genP12Ready( true );
    }
    
/*    
    self.convP12 = function () {
      self.outPKCSpem( null );
      clearError();
      self.convP12Ready( false );

      var form = document.forms.namedItem( "convP12form" ),
          fd = new FormData( form );

      fd.append( "action", "convP12" );

      plusRequest();
          
      $.ajax( {
        url: addr + suffix,
        type: "POST",
        data: fd,
        processData: false,
        contentType: false,
        dataType: "text",
        cache: false,
        success: function ( response ) {
          self.convP12Ready( true );
        },
        error: function ( xhr, type, error ) {
          self.errorMessage( error );
        },
        complete: function () {
          minusRequest();
        }
      } );
    
      return false;
    }    
*/    

    self.UpdateDBbtn = function () {
      if ( self.isUpdate() ) {
        /*  edit  */
        var index = self.DBList.indexOf( self.dbname() );
        console.log( index );
      } else {
        /*  create  */
        self.DBList.push( { name: self.dbname(),
                            desc: self.dbdesc(),
                            open: false } );        
      }
      
      self.tUpdateDB();
    }

    self.WipeDBbtn = function () {
      
    }
    
    self.openDB = function () {
      this.open = this.open ? false : true; 
    }
    
    self.editDB = function () {
      self.tUpdateDB();
      self.isUpdate( true );
      self.dbname( this.name );
      self.dbdesc( this.desc );
      self.dbopen( this.open );
    }
    
    self.removeDB = function () {
      self.DBList.remove( this );
    }


    /*  Helpers  */

    function cleanAll () {
      clearError();

      self.onAbout( false );
      self.onCA( false );
      self.onClient( false );
      self.onPKCS( false );
      self.onConfigure( false );      
    }

    function clearError () {
      self.errorMessage( null );
      self.errorDescription( null );
    }

    function plusRequest() {
      var n = self.onAJAX() ? self.onAJAX() : 0;
      self.onAJAX( n + 1 );
    }

    function minusRequest() {
      var n = self.onAJAX() ? self.onAJAX() : 1;
      self.onAJAX( n - 1 );
    }

    function getJSON ( url, cb ) {
      plusRequest();

      $.ajax( {
        type: 'GET',
        url: url,
        dataType: 'json',
        cache: false,
        success: cb,
        error: function ( xhr, type, error ) {
          self.errorMessage( error );
        },
        complete: function () {
          minusRequest();
        }
      } );
    }

    function postJSON ( url, payload, cb ) {
      plusRequest();

      $.ajax( {
        type: 'POST',
        url: url,
        data: payload,
        dataType: 'json',
        success: cb,
        error: function ( xhr, type, error ) {
          self.errorMessage( error );
        },
        complete: function () {
          minusRequest();
        }
      } );
    }
    
    function getRequest ( action, name, cb ) {
      getJSON( ra + 'action=' + action + '&name=' + name, function( data ) {
        if ( data.err == null ) {
          cb( data );
        } else {
          self.errorMessage( errors[ data.err ] );
        }
      } );
    }

    /*  Router functions  */

    function mainPage () {
      cleanAll();
      self.onAbout( true );
    }

    function caPage () {
      cleanAll();
      self.onCA( true );      
      self.inCAPassword() ? "" : self.inCAPassword( 'test' );
      self.inCADays() ? "" : self.inCADays( 365 );
      self.inCASubject()
        ? "" 
        : self.inCASubject( '/CN=' + window.location.host + '/O=plcrtd' );
      self.genCAkeyReady( true );
      self.genCAcrtReady( true );
    }

    function clientPage () {
      cleanAll();
      self.onClient( true );
      self.genClientKeyReady( true );
      self.genClientCrtReady( true );
      self.genClientCsrReady( true );
      self.inClientPassword() ? "" : self.inClientPassword( 'test' );
      self.inClientDays() ? "" : self.inClientDays( 365 );
      self.inClientSubject()
        ? ""
        : self.inClientSubject( '/CN=' + window.location.host );
      self.inClientSerial() ? "" : self.inClientSerial( '01' );
      self.inClientCAPassword() ? "" : self.inClientCAPassword( 'test' );
    }

    function pkcsPage () {
      cleanAll();
      self.onPKCS( true );
      self.genP12Ready( true );
      self.inPKCSClientPwd() ? "" : self.inPKCSClientPwd( 'test' );
      self.convP12Ready( true );
    }
    
    function configurePage () {
      cleanAll();
      self.onConfigure( true );
    }
    

    /*  Setup routers  */

    crossroads.addRoute( '', mainPage );
    crossroads.addRoute( '/', mainPage );
    var actionsRouter = crossroads.addRoute( '{action}' );

    actionsRouter.matched.add( function ( action ) {
      switch ( action ) {
        case 'ca':
          caPage();
          break;
        case 'client':
          clientPage();
          break;
        case 'pkcs':
          pkcsPage();
          break;
        case 'configure':
          configurePage();
          break;
        default:
          mainPage();
      }
    } );

    /*  Setup hasher  */

    function parseHash ( newHash, oldHash ) {
      /* location has been switched to '/' */
      if ( newHash == undefined || newHash === "" ) {
        cleanAll();
        mainPage();
      }

      crossroads.parse( newHash );
    }

    hasher.initialized.add( parseHash ); /* parse initial hash */
    hasher.changed.add( parseHash );     /* parse hash changes */
    hasher.init();                       /* start listening for history change */
  }

  ko.applyBindings( new AppViewModel() );

} );
