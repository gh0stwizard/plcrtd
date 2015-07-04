$( function() {
  var suffix = '/plcrtd',
      addr = window.location.protocol + '//' + window.location.host
      errors = [
        'Connection error',
        'Bad request',
        'Not implemented',
        'Internal error',
        'Invalid name',
        'Duplicate entry',
        'Entry not found'
      ],
      sizeOptions = [ 1024, 2048, 4096 ],
      pkOptions = [ 'RSA' ],
      cipherOptions = [ 'DES3', 'AES128', 'AES192', 'AES256' ];


  function sortByName( a, b ) {
    aName = $.isFunction( a.Name ) ? a.Name() : a.Name;
    bName = $.isFunction( b.Name ) ? b.Name() : b.Name;

    return ( aName == bName ) ? 0 : ( aName < bName ? -1 : 1 );
  }


  function Database ( options ) {
    this.defaults = { name: 'db1', desc: '' };
    options = $.extend( { }, this.defaults, options  );
    
    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );

    this.isActive = ko.observable( false );
  }


  function PrivateKey ( options ) {
    this.defaults = {
      name: 'key',
      type: 'RSA',
      size: 2048,
      cipher: 'AES256',
      passwd: null
    };
    options = $.extend( {}, this.defaults, options );
    
    this.Name = ko.observable( options.name );
    this.Type = ko.observable( options.type );
    this.Size = ko.observable( options.size );
    this.Cipher = ko.observable( options.cipher );
    this.Password = ko.observable( options.passwd );
    
    this.Encrypted = ko.pureComputed( {
      owner: this,
      read: function ( ) {
        return ( this.Password() ) ? 'Yes' : 'No';
      }
    } );
  }


  function Request ( options ) {
    this.defaults = { name: 'csr' };
    options = $.extend( {}, this.defaults, options );

    this.Name = ko.observable( options.name );
  }

  
  function Certificate ( options ) {
    this.defaults = { name: 'crt' };
    options = $( {}, this.defaults, options );

    this.Name = ko.observable( name );
  }

  
  function RevocationList ( options ) {
    this.defaults = { name: 'crl' };
    options = $.extend( {}, this.defaults, options );

    this.Name = ko.observable( name );
  }


  function Page ( args ) {
    this.defaults = { };
    this.args = $.extend( {}, this.defaults, args );

    this.onCreate = ko.observable( false );
    this.onWipe = ko.observable( false );
    this.onTable = ko.observable( false );
    this.List = ko.observableArray( [ ] );
    this.Item = ko.observable();
    
    this.CreateItem= args.CreateItem
      ? args.CreateItem.bind( this )
      : function ( ) { };
      
    function Create () {
      this.List.push( this.Item() );
      this.List.sort( sortByName );
      this.CreateToggle();
    }

    this.Create = $.isFunction( args.Create ) 
      ? args.Create.bind( this )
      : Create.bind( this );
    
    function Remove ( item ) {
      this.List.remove( item );
    }
    
    this.Remove = $.isFunction( args.Remove )
      ? args.Remove.bind( this )
      : Remove.bind( this );
    
    function Wipe () {
      this.List.removeAll();
      this.WipeToggle();
    }

    this.Wipe = $.isFunction( args.Wipe )
      ? args.Wipe.bind( this )
      : Wipe.bind( this );

    function CreateToggle () {
      this.onWipe( false );

      if ( this.onCreate() ) {
        this.onCreate( false );
        this.onTable( true );
        this.Item( null );
      } else {
        this.onCreate( true );
        this.onTable( false );
        this.Item( this.CreateItem() );
      }

      return false;
    }

    this.CreateToggle = CreateToggle.bind( this );

    function WipeToggle () {
      this.onCreate( false );

      if ( this.onWipe() ) {
        this.onWipe( false );
        this.onTable( true );
      } else {
        this.onWipe( true );
        this.onTable( false );
      }

      return false;
    }
    
    this.WipeToggle = WipeToggle.bind( this );
  }
  

  function AppViewModel() {
    var self = this;

    /*  Data  */

    self.onAJAX = ko.observable( 0 );
    self.errorMessage = ko.observable();
    self.errorDescription = ko.observable();

    /*  Data: show page toggles  */

    self.onAbout = ko.observable( false );
    self.onConfigure = ko.observable( false );
    self.onPrivateKeys = ko.observable( false );
    self.onRequests = ko.observable( false );
    self.onCertificates = ko.observable( false );
    self.onRevoked = ko.observable( false );


    /*  Behaviours  */

    self.About  =       function () { location.hash = 'about';        }
    self.Configure =    function () { location.hash = 'configure';    }
    self.PrivateKeys =  function () { location.hash = 'privatekeys';  }
    self.Requests =     function () { location.hash = 'requests';     }
    self.Certificates = function () { location.hash = 'certificates'; }
    self.Revoked =      function () { location.hash = 'revoked';      }


    /*  Behaviours: Configuration  */
    
    self.cfg = new Page( {
      CreateItem : function () { return new Database(); },
      Create : function () {
        var iam = this,
            db = iam.Item();

        clearError();

        postJSON( {
          action: 'createdb',
          name: db.Name(),
          desc: db.Description()
        },
        function ( response ) {
          if ( response.name ) {
            iam.List.push( db );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err );
          }
        } );
      },
      Remove : function ( db ) {
        var iam = this,
            name = db.Name();

        clearError();

        postJSON( {
          action: 'removedb',
          name: name
        },
        function ( response ) {
          if ( response.name ) {
            if ( iam.Settings().Name() === name ) {
              iam.Settings( null );
            }

            iam.List.remove( db );
          } else {
            self.errorMessage( errors[ response.err ] );
          }
        } );
      },
      Wipe : function ( ) {
        var iam = this;

        clearError();

        postJSON( { action: 'removealldb' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.Settings( null );
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            self.errorMessage( errors[ response.err ] );
          }
        } );
      }
    } );
    
    function ActivateDB ( db ) {
      var iam = this,
          name = db.Name();

      clearError();

      postJSON( {
        action: 'switchdb',
        name: name
      },
      function ( response ) {
        if ( response.name ) {
          var dbs = iam.List(),
              len = dbs.length;

          /* mark all as an inactive */
          for ( var i = 0; i < len; i++ ) {
            dbs[i].isActive( false );
          }
      
          /* activate choosen db */
          db.isActive( true );
      
          /* retrieve settings */
          iam.Settings( db );
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }
    
    function SetupDB ( ) {
      var iam = this,
          db = iam.Settings(),
          name = db.Name(),
          desc = db.Description();

      clearError();

      postJSON( {
        action: 'updatedb',
        name: name,
        desc: desc
      },
      function ( response ) {
        if ( response.name ) {
          /* nop */
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    function ListDBs ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'listdbs' }, function ( response ) {
        if ( response.dbs ) {
          var list = response.dbs,
              total = list.length;

          for ( var i = 0; i < total; i++ ) {
            var db = list[i];
            iam.List.push( new Database( { 
              name: db.name,
              desc: db.desc
            } ) );
          }

          iam.List.sort( sortByName );
          iam.Current();
        }
      } );
    }

    function CurrentDB ( ) {
      var iam = this;

      clearError();

      postJSON( { action: 'currentdb' }, function ( response ) {
        if ( response.name ) {
          var dbs = iam.List(),
              len = dbs.length,
              name = response.name;

          for ( var i = 0; i < len; i++ ) {
            var db = dbs[i];

            if ( db.Name() === name ) {
              db.isActive( true );
              iam.Settings( db );
              break;
            }
          }
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    $.extend( self.cfg, {
      Activate: ActivateDB.bind( self.cfg ),
      Settings: ko.observable(),
      Setup: SetupDB.bind( self.cfg ),
      ListDBs: ListDBs.bind( self.cfg ),
      Current: CurrentDB.bind( self.cfg )
    } );

    
    /*  Behaviours: Private Keys  */

    self.pk = new Page( {
      CreateItem : function () { return new PrivateKey(); },
      Create : function () {
        var iam = this;
        var key = iam.Item();

        clearError();
      
        postJSON( { 
          action: 'genkey',
          type: key.Type(),
          bits: key.Size(),
          cipher: key.Cipher(),
          passwd: key.Password()
        },
        function ( response ) {
          if ( response.key ) {
            iam.List.push( key );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            self.errorMessage( errors[ response.err ] );
            self.errorDescription( response.msg );
          }
        } );
      },
      Remove : function ( pk ) {
        this.List.remove( pk );
      },
      Wipe : function () {
        this.List.removeAll();
        this.WipeToggle();
      }
    } );
    
    
    /*  Behaviours: Requests  */
    
    self.csr = new Page( {
      CreateItem : function () { return new Request(); }
    } );
    

    /*  Behaviours: Certificates  */
    
    self.crt = new Page( {
      CreateItem : function () { return new Certificate(); }
    } );


    /*  Behaviours: Revocation Lists  */
    
    self.crl = new Page( {
      CreateItem : function () { return new RevocationList(); }
    } );


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

    function riseError ( ) {
      self.errorMessage( errors[ arguments[0] ] );

      if ( arguments.length > 1 ) {
        self.errorDescription( arguments[1] );
      }

      return false;
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
          self.cfg.onTable( true );
          self.cfg.ListDBs();
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
