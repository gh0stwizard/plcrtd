$( function() {
  var suffix = '/plcrtd',
      addr = window.location.protocol + '//' + window.location.host
      errors = [
        'Connection error',
        'Bad request',
        'Not implemented',
        'Internal error'
      ],
      sizeOptions = [ 1024, 2048, 4096 ],
      pkOptions = [ 'RSA', 'DSA' ];

  function sortByName( a, b ) {
    return ( a.name()() == b.name()() ) ? 0 : ( a.name()() < b.name()() ? -1 : 1 );
  }

  function Database ( n, d ) {
    var db = this;

    db.name = ko.observable( n );
    db.description = ko.observable( d );
    db.isActive = ko.observable( false );
    db.editing = ko.observable( false );
    db.edit = function () {
      this.editing( true );
    };

    return db;
  }
  
  function DatabaseSetup ( name ) {
    var setup = this;
    
    setup.dbname = name;
    setup.capath = ko.observable( '/path/to/ca.key' );
    
    return setup;
  }


  function PrivateKey ( name, type, size ) {
    var pk = this;
    
    pk.name = ko.observable( name );
    pk.type = ko.observable( type );
    pk.size = ko.observable( size );
    
    return pk;
  }
  
  
  function Request ( name ) {
    var req = this;
    
    req.name = ko.observable( name );
    
    return req;
  }

  
  function Certificate ( name ) {
    var cert = this;
    
    cert.name = ko.observable( name );
    
    return cert;
  }

  
  function RevocationList ( name ) {
    var rl = this;
    
    rl.name = ko.observable( name );
    
    return rl;
  }


  function AppViewModel() {
    var self = this;

    /*  Data  */

    self.onAJAX = ko.observable( 0 );
    self.errorMessage = ko.observable();
    self.errorDescription = ko.observable();

    /*  Data: show page toggles  */

    self.onAbout = ko.observable( false );
    self.onPrivateKeys = ko.observable( false );
    self.onRequests = ko.observable( false );
    self.onCertificates = ko.observable( false );
    self.onRevoked = ko.observable( false );

    /*  Data: Configure Page  */

    self.onConfigure = ko.observable( false );
    self.onCreateDB = ko.observable( false );
    self.onWipeDBs = ko.observable( false );

    /*  Data: Configure Page: DB management  */

    self.DB = ko.observable();
    self.DBList = ko.observableArray( [ ] );
    self.onDBTable = ko.observable( false );
    self.DBsetup = ko.observable();

    /*  Data: Private Keys  */
    
    self.onCreatePK = ko.observable( false );
    self.onWipePKs = ko.observable( false );
    self.onPKTable = ko.observable( false );
    self.PKList = ko.observableArray( [ ] );
    self.PK = ko.observable();

    /*  Data: Requests  */
    
    self.onCreateRQ = ko.observable( false );
    self.onWipeRQs = ko.observable( false );
    self.onRQTable = ko.observable( false );
    self.RQList = ko.observableArray( [ ] );
    self.RQ = ko.observable();

    /*  Data: Certificates  */
    
    self.onCreateCR = ko.observable( false );
    self.onWipeCRs = ko.observable( false );
    self.onCRTable = ko.observable( false );
    self.CRList = ko.observableArray( [ ] );
    self.CR = ko.observable();

    /*  Data: Revoked  */
    
    self.onCreateRL = ko.observable( false );
    self.onWipeRLs = ko.observable( false );
    self.onRLTable = ko.observable( false );
    self.RLList = ko.observableArray( [ ] );
    self.RL = ko.observable();


    /*  Behaviours  */

    self.About  =       function () { location.hash = 'about';        }
    self.Configure =    function () { location.hash = 'configure';    }
    self.PrivateKeys =  function () { location.hash = 'privatekeys';  }
    self.Requests =     function () { location.hash = 'requests';     }
    self.Certificates = function () { location.hash = 'certificates'; }
    self.Revoked =      function () { location.hash = 'revoked';      }

    /*  Behaviours: Configuration  */
    
    /* Create DB button toggle */
    self.btnCreateDB = function () {
      self.onWipeDBs( false );

      if ( self.onCreateDB() ) {
        self.onCreateDB( false );
        self.onDBTable( true );
        self.DB( null );
      } else {
        self.onCreateDB( true );
        self.onDBTable( false );
        self.DB( new Database( 'db', '' ) );
      }

      return false;
    }

    /* Wipe DBs button toggle */
    self.btnWipeDBs = function () {
      self.onCreateDB( false );

      if ( self.onWipeDBs() ) {
        self.onWipeDBs( false );
        self.onDBTable( true );
      } else {
        self.onWipeDBs( true );
        self.onDBTable( false );
      }

      return false;
    }

    self.CreateDB = function () {
      var db = self.DB(),
          name = db.name,
          desc = db.description;

      self.DBList.push( new Database( name, desc ) );
      self.DBList.sort( sortByName );
      self.btnCreateDB();

      return false;
    }

    self.UpdateDB = function ( ) {
      /*  XXX  */
      var name = this.name()(),
          desc = this.description()();
      
      console.log( 'updating: ' + name );
      
    }
    
    self.RemoveDB = function ( db ) {
      /*  XXX  */
      var name = this.name()();
      
      console.log( 'removing: ' + name );
      
      self.DBList.remove( db );
    }

    self.WipeDBs = function () {
      self.DBList.removeAll();
      self.DBsetup( null );
      self.btnWipeDBs();
    }
    
    self.ActivateDB = function ( db ) {
      var name = db.name()();
      console.log( 'activating: ' + name );
      self.DBsetup( new DatabaseSetup( name ) );
      
      var dbs = self.DBList(),
          len = dbs.length;

      for ( var i = 0; i < len; i++ ) {
        dbs[i].isActive( false );
      }
      
      db.isActive( true );
    }
    
    self.SetupDB = function () {
      var setup = self.DBsetup(),
          name = setup.dbname;

      console.log( 'setupdb, db = ' + name );
      
      return false;
    }
    
    
    /*  Behaviours: Private Keys  */
    
    self.btnCreatePK = function () {
      self.onWipePKs( false );

      if ( self.onCreatePK() ) {
        self.onCreatePK( false );
        self.onPKTable( true );
        self.PK( null );
      } else {
        self.onCreatePK( true );
        self.onPKTable( false );
        self.PK( new PrivateKey( 'key', 'RSA', 1024 ) );
      }

      return false;    
    }
    
    self.btnWipePKs = function () {
      self.onCreatePK( false );

      if ( self.onWipePKs() ) {
        self.onWipePKs( false );
        self.onPKTable( true );
      } else {
        self.onWipePKs( true );
        self.onPKTable( false );
      }

      return false;    
    }
    
    self.CreatePK = function () {
      var pk = self.PK(),
          name = pk.name,
          type = pk.type,
          size = pk.size;

      self.PKList.push( new PrivateKey( name, type, size ) );
      self.PKList.sort( sortByName );
      self.btnCreatePK();

      return false;    
    }
    
    self.RemovePK = function ( pk ) {
      /*  XXX  */
      var name = this.name()();
      
      console.log( 'removing: ' + name );
      
      self.PKList.remove( pk );
    }
    
    self.WipePKs = function () {
      self.PKList.removeAll();
      self.btnWipePKs();
    }
    
    
    /*  Behaviours: Requests  */
    
    self.btnCreateRQ = function () {
      self.onWipeRQs( false );

      if ( self.onCreateRQ() ) {
        self.onCreateRQ( false );
        self.onRQTable( true );
        self.RQ( null );
      } else {
        self.onCreateRQ( true );
        self.onRQTable( false );
        self.RQ( new Request( 'csr' ) );
      }

      return false;    
    }
    
    self.btnWipeRQs = function () {
      self.onCreateRQ( false );

      if ( self.onWipeRQs() ) {
        self.onWipeRQs( false );
        self.onRQTable( true );
      } else {
        self.onWipeRQs( true );
        self.onRQTable( false );
      }

      return false;    
    }
    
    self.CreateRQ = function () {
      var csr = self.RQ(),
          name = csr.name;

      self.RQList.push( new Request( name ) );
      self.RQList.sort( sortByName );
      self.btnCreateRQ();

      return false;    
    }
    
    self.RemoveRQ = function ( req ) {
      /*  XXX  */
      var name = this.name()();
      
      console.log( 'removing: ' + name );
      
      self.RQList.remove( req );
    }
    
    self.WipeRQs = function () {
      self.RQList.removeAll();
      self.btnWipeRQs();
    }


    /*  Behaviours: Certificates  */
    
    self.btnCreateCR = function () {
      self.onWipeCRs( false );

      if ( self.onCreateCR() ) {
        self.onCreateCR( false );
        self.onCRTable( true );
        self.CR( null );
      } else {
        self.onCreateCR( true );
        self.onCRTable( false );
        self.CR( new Certificate( 'Request' ) );
      }

      return false;    
    }
    
    self.btnWipeCRs = function () {
      self.onCreateCR( false );

      if ( self.onWipeCRs() ) {
        self.onWipeCRs( false );
        self.onCRTable( true );
      } else {
        self.onWipeCRs( true );
        self.onCRTable( false );
      }

      return false;    
    }
    
    self.CreateCR = function () {
      var cert = self.CR(),
          name = cert.name;

      self.CRList.push( new Certificate( name ) );
      self.CRList.sort( sortByName );
      self.btnCreateCR();

      return false;
    }
    
    self.RemoveCR = function ( req ) {
      /*  XXX  */
      var name = this.name()();
      
      console.log( 'removing: ' + name );
      
      self.CRList.remove( req );
    }
    
    self.WipeCRs = function () {
      self.CRList.removeAll();
      self.btnWipeCRs();
    }


    /*  Helpers  */

    function cleanAll () {
      clearError();
      self.onAbout( false );
      self.onConfigure( false );
      self.onPrivateKeys( false );
      self.onRequests( false );
      self.onCertificates( false );
      self.onRevoked( false );
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

    function postJSON ( payload, success_cb ) {
      plusRequest();

      $.ajax( {
        type: 'POST',
        url: addr + suffix,
        data: payload,
        dataType: 'json',
        success: success_cb,
        error: function ( xhr, type, error ) {
          self.errorMessage( error );
        },
        complete: function () {
          minusRequest();
        }
      } );
    }
    
    /*  Router functions  */
    
    function mainPage () { location.hash = 'about'; }

    /*  Setup routers  */

    crossroads.addRoute( '', mainPage );
    crossroads.addRoute( '/', mainPage );

    var pagesRouter = crossroads.addRoute( '{action}' );
    pagesRouter.matched.add( function ( action ) {
      cleanAll();
    
      switch ( action ) {
        case 'configure':
          self.onConfigure( true );
          self.DBList.sort( sortByName );
          break;
        case 'privatekeys':
          self.onPrivateKeys( true );
          break;
        case 'certificates':
          self.onCertificates( true );
          break;
        case 'requests':
          self.onRequests( true );
          break;
        case 'revoked':
          self.onRevoked( true );
          break;
        case 'about':
          self.onAbout( true );
          break;
        default:
          mainPage();
      }
    } );

    /*  Setup hasher  */

    function parseHash ( newHash, oldHash ) {
      if ( newHash == undefined || newHash === "" ) {
        /* location has been switched to '/' */
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
