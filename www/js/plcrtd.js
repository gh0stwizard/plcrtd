$( function() {
  var suffix = '/plcrtd',
      addr = window.location.protocol + '//' + window.location.host
      errors = [
        'No error',
        'Bad request',
        'Not implemented',
        'Internal error',
        'Invalid name',
        'Duplicate entry',
        'Entry not found'
      ],
      sizeOptions = [ 1024, 2048, 4096 ],
      pkOptions = [ 'RSA' ], /* DSA is not implemented on server side yet */
      cipherOptions = [
        'DES3',
        'AES128',
        'AES192',
        'AES256'
      ],
      digestOptions = [ 
        'MD5',
        'SHA1',
        'SHA224',
        'SHA256',
        'SHA384',
        'SHA512',
        'RIPEMD160'
      ],
      templateOptions = [ 'Default', 'Self-signed' ];


  function sortByName( a, b ) {
    aName = $.isFunction( a.Name ) ? a.Name() : a.Name;
    bName = $.isFunction( b.Name ) ? b.Name() : b.Name;

    return ( aName == bName ) ? 0 : ( aName < bName ? -1 : 1 );
  }


  function Database ( options ) {
    this.defaults = {
      name: 'db1',
      desc: ''
    };
    options = $.extend( { }, this.defaults, options  );
    
    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );

    this.isActive = ko.observable( false );
  }


  function PrivateKey ( options ) {
    this.defaults = {
      id:       null,
      name:     'key1',
      type:     'RSA',
      size:     2048,
      cipher:   'AES256',
      passwd:   null
    };
    options = $.extend( { }, this.defaults, options );

    this.Name     = ko.observable( options.name );
    this.Type     = ko.observable( options.type );
    this.Size     = ko.observable( options.size );
    this.Cipher   = ko.observable( options.cipher );
    this.Password = ko.observable( options.passwd );
    this.ID       = ko.observable( options.id );

    this.Encrypted = ko.pureComputed
    ({
        owner: this,
        read: function ( ) {
          return ( this.Password() ) ? 'Yes' : 'No';
        }
    });
  }


  function Request ( options ) {
    this.defaults = { 
      name:     'csr1',
      keyname:  '',
      keypass:  '',
      subject:  '/CN=plcrtd',
      digest:   'SHA256'
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.KeyName = ko.observable( options.keyname );
    this.KeyPassword = ko.observable( options.keypass );
    this.Subject = ko.observable( options.subject );
    this.Digest = ko.observable( options.digest );
  }

  
  function Certificate ( options ) {
    this.defaults = {
      name:     'crt1',
      desc:     '',
      days:     30,
      serial:   -1,
      /* common certificate options */
      keyname:  '',
      keypass:  '',
      subject:  '/CN=plcrtd',
      digest:   'SHA256',
      /* self-signed certificate options */
      csrname:  '',
      cacrt:    '',
      cakey:    '',
      cakeypw:  '',
      template: 'Default',
      incrl:    [ ]
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );
    this.Days = ko.observable( options.days );
    this.Serial = options.serial;

    /* common */
    this.KeyName = ko.observable( options.keyname );
    this.KeyPassword = ko.observable( options.keypass );
    this.Subject = ko.observable( options.subject );
    this.Digest = ko.observable( options.digest );

    /* self-signed */
    this.CsrName = ko.observable( options.csrname );
    this.CACrtName = ko.observable( options.cacrt );
    this.CAKeyName = ko.observable( options.cakey );
    this.CAKeyPassword = ko.observable( options.cakeypw );

    this.Template = ko.observable( options.template );
    this.inCRL = ko.observableArray( options.incrl );
  }


  function RevocationList ( options ) {
    this.defaults = {
      name:     'crl1',
      desc:     '',
      days:     30,
      cacrt:    '',
      cakey:    '',
      cakeypw:  ''
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );
    this.Days = ko.observable( options.days );
    this.CACrtName = ko.observable( options.cacrt );
    this.CAKeyName = ko.observable( options.cakey );
    this.CAKeyPassword = ko.observable( options.cakeypw );
  }


  function Deploy ( options ) {
    this.defaults = {
      name: 'deploy1',
      host: 'localhost'
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.Host = ko.observable( options.host );
  }


  function Export ( options ) {
    this.defaults = {
      /* TODO */
    };
    options = $.extend( { }, this.defaults, options );

  }


  function Page ( args ) {
    this.defaults = { };
    this.args = $.extend( { }, this.defaults, args );

    this.onCreate = ko.observable( false );
    this.onWipe = ko.observable( false );
    this.onTable = ko.observable( false );
    this.onSetup = ko.observable( false );
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
        this.onSetup( true );
        this.Item( null );
      } else {
        this.onCreate( true );
        this.onTable( false );
        this.onSetup( false );
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
        this.onSetup( true );
      } else {
        this.onWipe( true );
        this.onTable( false );
        this.onSetup( false );
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
    self.onCRL = ko.observable( false );
    self.onDeploy = ko.observable( false );
    self.onExport = ko.observable( false );


    /* Header */
    self.chapters = [
      'About',
      'Private keys',
      'CSR',
      'Certificates',
      'CRL',
      'Deploy',
      'Export'
    ];


    /*  Behaviours: chapters  */
    self.selectChapter = function ( chapter ) { location.hash = chapter }


    /*  Behaviours: Private Keys  */
    self.pk = new Page( {
      CreateItem : function () { return new PrivateKey(); },
      Create : function () {
        var iam     = this,
            key     = iam.Item(),
            name    = key.Name(),
            type    = key.Type(),
            size    = key.Size(),
            cipher  = key.Cipher(),
            passwd  = key.Password();

        clearError();

        postJSON
        (
          {
            action: 'CreateKey',
            name:   name,
            type:   type,
            bits:   size,
            cipher: cipher,
            passwd: passwd
          },
          function ( response ) {
            if ( 'data' in response ) {
              iam.List.push( key );
              iam.List.sort( sortByName );
              iam.CreateToggle();
            } else {
              riseError( response.err, response.msg );
            }
          }
        );
      },
      Remove : function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'RemoveKey',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe : function () {
        var iam = this;

        clearError();

        postJSON( { action: 'RemoveAllKeys' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );

    function ListPrivateKeys ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON
      (
        {
          action: 'ListKeys'
        },
        function ( response ) {
          if ( 'data' in response ) {
            var ary = response.data,
                len = ary.length;

            for ( var i = 0; i < len; i++ ) {
              iam.List.push( new PrivateKey( ary[i] ) );
            }

            iam.List.sort( sortByName );
          } else {
            riseError( response.err );
          }
        }
      );
    }

    $.extend( self.pk, {
      ListPKs: ListPrivateKeys.bind( self.pk )
    } );


    /*  Behaviours: Requests  */

    self.csr = new Page( {
      CreateItem : function () { return new Request(); },
      Create : function ( ) {
        var iam = this,
            item = iam.Item(),
            payload = {
              action:   'gencsr',
              name:     item.Name(),
              keyname:  item.KeyName(),
              keypass:  item.KeyPassword(),
              subject:  item.Subject(),
              digest:   item.Digest()
            };

        clearError();

        postJSON( payload, function ( response ) {
          if ( 'name' in response ) {
            iam.List.push( item );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove : function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'RemoveCSR',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe : function () {
        var iam = this;

        clearError();

        postJSON( { action: 'RemoveAllCSRs' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );


    function GetKeys ( ) {
      var iam = this;

      clearError();
      iam.Keys.removeAll();

      postJSON( { action: 'ListKeys' }, function ( response ) {
        if ( 'keys' in response ) {
          var ary = response.keys,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.Keys.push( ary[i].name );
          }

          iam.Keys.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    function ListCertificateRequests ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'ListCSRs' }, function ( response ) {
        if ( 'csrs' in response ) {
          var ary = response.csrs,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new Request( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }

    $.extend( self.csr, {
      Keys : ko.observableArray( [ ] ),
      GetKeys  : GetKeys.bind( self.csr ),
      ListCSRs : ListCertificateRequests.bind( self.csr )
    } );


    /*  Behaviours: Certificates  */
    
    self.crt = new Page( {
      CreateItem: function () { return new Certificate(); },
      Create: function ( ) {
        var iam = this,
            item = iam.Item(),
            template = item.Template(),
            payload,
            defaults = {
              action:   'gencrt',
              name:     item.Name(),
              desc:     item.Description(),
              days:     item.Days(),
              template: template
            };

        if ( template == 'Default' ) {
          payload = {
            keyname:  item.KeyName(),
            keypass:  item.KeyPassword(),
            subject:  item.Subject(),
            digest:   item.Digest()
          };
        } else {
          payload = {
            cacrt:    item.CACrtName(),
            cakey:    item.CAKeyName(),
            cakeypw:  item.CAKeyPassword(),
            csrname:  item.CsrName()
          };
        }

        payload = $.extend( { }, defaults, payload );

        clearError();

        postJSON( payload, function ( response ) {
          if ( 'name' in response ) {
            /* update serial */
            item.Serial = iam.Serial();
            iam.GetSerial();

            iam.List.push( item );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove: function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'RemoveCRT',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.GetSerial();
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe: function () {
        var iam = this;

        clearError();

        postJSON( { action: 'RemoveAllCRTs' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.GetSerial();
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );

    function ListCertificates ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'ListCRTs' }, function ( response ) {
        if ( 'crts' in response ) {
          var ary = response.crts,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new Certificate( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }

    function GetCSRs ( ) {
      var iam = this;

      clearError();
      iam.CSRs.removeAll();

      postJSON( { action: 'ListCSRs' }, function ( response ) {
        if ( 'csrs' in response ) {
          var ary = response.csrs,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.CSRs.push( ary[i].name );
          }

          iam.CSRs.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }


    function GetCRLs ( ) {
      var iam = this;

      clearError();
      iam.CRLs.removeAll();

      postJSON( { action: 'ListCRLs' }, function ( response ) {
        if ( 'crls' in response ) {
          var ary = response.crls,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.CRLs.push( ary[i].name );
          }

          iam.CRLs.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }


    function ComputeCrtNames ( ) {
      var result = new Array(),
          crts = this.List(),
          length = crts.length;

      for ( var i = 0; i < length; i++ ) {
        result.push( crts[i].Name() );
      }

      return result;
    }


    function GetSerial ( ) {
      var iam = this;

      clearError();
      iam.Serial( null );

      postJSON( { action: 'GetSerial' }, function ( response ) {
        if ( 'serial' in response ) {
          iam.Serial( response.serial );
        } else {
          riseError( response.err, response.msg );
        }
      } );

      return false;
    }


    function RevokeCRTToggle ( crt ) {
      var iam = this;

      if ( iam.onRevoke() ) {
        iam.Item( null );
        iam.onRevoke( false );
        iam.onTable( true );
      } else {
        iam.Item( crt );
        iam.onRevoke( true );
        iam.onTable( false );
      }

      return false;
    }


    function AddCRTtoCRL ( ) {
      var iam = this,
          item = iam.Item(),
          crlName = iam.CRLName(),
          payload = {
            action: 'AddToCRL',
            name:   item.Name(),
            crl:    crlName
          };

      clearError();
      iam.CRLName( null );

      postJSON( payload, function ( response ) {
        if ( 'name' in response ) {
          item.inCRL.push( crlName );
        } else {
          riseError( response.err, response.msg );
        }

        iam.RevokeToggle();
      } );
    }


    function RemoveCRTfromCRL ( ) {
      var iam = this,
          item = iam.Item(),
          crlName = iam.CRLName(),
          payload = {
            action: 'RemoveFromCRL',
            name:   item.Name(),
            crl:    crlName
          };

      clearError();
      iam.CRLName( null );

      postJSON( payload, function ( response ) {
        if ( 'name' in response ) {
          item.inCRL.remove( crlName );
        } else {
          riseError( response.err, response.msg );
        }

        iam.UndoRevokeToggle();
      } );
    }


    function UndoRevokeCRTToggle ( crt ) {
      var iam = this;

      if ( iam.onUndoRevoke() ) {
        iam.Item( null );
        iam.onUndoRevoke( false );
        iam.onTable( true );
      } else {
        iam.Item( crt );
        iam.onUndoRevoke( true );
        iam.onTable( false );
      }

      return false;
    }


    $.extend( self.crt, {
      ListCRTs:         ListCertificates.bind( self.crt ),
      Keys:             ko.observableArray( [ ] ),
      GetKeys:          GetKeys.bind( self.crt ),
      CSRs:             ko.observableArray( [ ] ),
      GetCSRs:          GetCSRs.bind( self.crt ),
      CRTs:             ko.computed( ComputeCrtNames.bind( self.crt ) ),
      Serial:           ko.observable( 1 ),
      GetSerial:        GetSerial.bind( self.crt ),
      onRevoke:         ko.observable( false ),
      RevokeToggle:     RevokeCRTToggle.bind( self.crt ),
      AddToCRL:         AddCRTtoCRL.bind( self.crt ),
      CRLs:             ko.observableArray( [ ] ),
      GetCRLs:          GetCRLs.bind( self.crt ),
      CRLName:          ko.observable(),
      RemoveFromCRL:    RemoveCRTfromCRL.bind( self.crt ),
      onUndoRevoke:     ko.observable( false ),
      UndoRevokeToggle: UndoRevokeCRTToggle.bind( self.crt )
    } );


    /*  Behaviours: Revocation Lists  */

    self.crl = new Page( {
      CreateItem: function ( ) { return new RevocationList(); },
      Create: function ( ) {
        var iam = this,
            item = iam.Item(),
            payload = {
              action:   'CreateCRL',
              name:     item.Name(),
              desc:     item.Description(),
              days:     item.Days(),
              cacrt:    item.CACrtName(),
              cakey:    item.CAKeyName()
            };

        clearError();

        postJSON( payload, function ( response ) {
          if ( 'name' in response ) {
            iam.List.push( item );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove: function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'RemoveCRL',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe: function ( ) {
        var iam = this;

        clearError();

        postJSON( { action: 'RemoveAllCRLs' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );


    function ListCRLs ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'ListCRLs' }, function ( response ) {
        if ( 'crls' in response ) {
          var ary = response.crls,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new RevocationList( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }


    function GetCRTs ( ) {
      var iam = this;

      clearError();
      iam.CRTs.removeAll();

      postJSON( { action: 'ListCRTs' }, function ( response ) {
        if ( 'crts' in response ) {
          var ary = response.crts,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.CRTs.push( ary[i].name );
          }

          iam.CRTs.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    $.extend( self.crl, {
      ListCRLs:   ListCRLs.bind( self.crl ),
      CRTs:       ko.observableArray( [ ]),
      GetCRTs:    GetCRTs.bind( self.crl ),
      Keys:       ko.observableArray( [ ] ),
      GetKeys:    GetKeys.bind( self.crl )
    } );


    /*  Behaviours: Deploy  */


    self.dpl = new Page( {
      CreateItem: function ( ) { return new Deploy(); },
    } );


    function DeployIt ( ) {
      var iam = this,
          item = iam.Item(),
          payload = {
            action:   'Deploy',
            name:     item.Name(),
            host:     item.Host()
          };

      clearError();

      postJSON( payload, function ( response ) {
        if ( 'name' in response ) {

          alert( 'Deploy Ok!' );

        } else {
          riseError( response.err, response.msg );
        }

        return false;
      } );      
    }


    function DeployLocalToggle ( ) {
      this.Item( this.CreateItem() );
      this.onLocal( ! this.onLocal() );
      this.onRemote( false );
    }


    function DeployRemoteToggle ( ) {
      this.Item( this.CreateItem() );
      this.onRemote( ! this.onRemote() );
      this.onLocal( false );
    }


    $.extend( self.dpl, {
      onLocal:      ko.observable( false ),
      onRemote:     ko.observable( false ),
      Deploy:       DeployIt.bind( self.dpl ),
      LocalToggle:  DeployLocalToggle.bind( self.dpl ),
      RemoteToggle: DeployRemoteToggle.bind( self.dpl )
    } );


    /*  Behaviours: Export  */


    self.exp = new Page( {
      CreateItem: function ( ) { return new Export(); },
    } );


    /*  Helpers  */

    function cleanAll () {
      clearError();
      clearData();
      self.onAbout( false );
      self.onConfigure( false );
      self.onPrivateKeys( false );
      self.onRequests( false );
      self.onCertificates( false );
      self.onCRL( false );
      self.onDeploy( false );
      self.onExport( false );
    }


    function clearError ( ) {
      self.errorMessage( null );
      self.errorDescription( null );
    }


    function clearData ( ) {
/*      self.cfg.Settings( null );*/
    }


    function riseError ( ) {
      self.errorMessage( errors[ arguments[0] ] );

      if ( arguments.length > 1  && arguments[1] ) {
        self.errorDescription( arguments[1] );
      }

      /* cleanup 
      self.cfg.Settings( null );*/

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

    function mainPage () { location.hash = 'About'; }


    /*  Setup routers  */

    crossroads.addRoute( '', mainPage );
    crossroads.addRoute( '/', mainPage );

    var pagesRouter = crossroads.addRoute( '{action}' );
    pagesRouter.matched.add( function ( action ) {
      cleanAll();

      switch ( action ) {
        case 'Private keys':
          self.onPrivateKeys( true );
          self.pk.onTable( true );
          self.pk.onCreate( false );
          self.pk.onWipe( false );
          self.pk.ListPKs();
          break;
        case 'CSR':
          self.onRequests( true );
          self.csr.onTable( true );
          self.csr.onCreate( false );
          self.csr.onWipe( false );
          self.csr.GetKeys();
          self.csr.ListCSRs();
          break;
        case 'Certificates':
          self.onCertificates( true );
          self.crt.onTable( true );
          self.crt.onCreate( false );
          self.crt.onWipe( false );
          self.crt.GetKeys();
          self.crt.GetCSRs();
          self.crt.GetCRLs();
          self.crt.GetSerial();
          self.crt.ListCRTs();
          break;
        case 'CRL':
          self.onCRL( true );
          self.crl.onTable( true );
          self.crl.onCreate( false );
          self.crl.onWipe( false );
          self.crl.GetCRTs();
          self.crl.GetKeys();
          self.crl.ListCRLs();
          break;
        case 'About':
          self.onAbout( true );
          break;
        case 'Deploy':
          self.onDeploy( true );
          break;
        case 'Export':
          self.onExport( true );
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
